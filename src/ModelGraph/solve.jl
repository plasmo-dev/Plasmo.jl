#This file contains all of the constructs to create and manage a JuMP GraphModel.  The idea is that you use PLASMO to create your graph, associate models, and build the
#flattened model which JuMP can always solve in serial.
import MathProgBase
#import MathOptInterface (soon)
import LightGraphs
using JuMP
import JuMP:setvalue,solve


#IDEA : If solving with JuMP: Create the corresponding JuMP model and return the solution to the graph

#If solving with a MathProgBase compliant solver, convert the model graph to a flattened JuMP Model, solve that, and pass the result back to the ModelGraph
mutable struct JuMPGraph <: AbstractModelGraph
    basegraph::BasePlasmoGraph
    linkconstraints::Vector{ConstraintRef}
end
JuMPGraph() = JuMPGraph(BasePlasmoGraph(HyperGraph),ConstraintRef[])
JuMPGraph(basegraph::BasePlasmoGraph) = JuMPGraph(basegraph,ConstraintRef[])

mutable struct JuMPNode <: AbstractModelNode
    basenode::BasePlasmoNode
    objective#::AffExpr                           #Individual node objective expression.
    variablemap::Dict{Symbol,Any}                 #Dictionary of symbols to JuMP Model variables.  Might make sense to use JuMP containers here
    variablelist::Vector{AbstractJuMPScalar}
    constraintlist::Vector{ConstraintRef}         #Vector of model constraints (make this a dictionary too)
    indexmap::Dict{Int,Int}                       #linear index of node variable in flat model to the original index of the component model
end
create_node(graph::JuMPGraph) = JuMPNode(BasePlasmoNode(),0,Dict{Symbol,AbstractJuMPScalar}(),AbstractJuMPScalar[],ConstraintRef[],Dict{Int,Int}())
hasmodel(node::JuMPNode) = throw(error("JuMP nodes are simple references to original ModelNodes.  Did you mean to check a ModelNode?"))

#Has constraint references for link constraints
mutable struct JuMPEdge <: AbstractLinkingEdge
    baseedge::BasePlasmoEdge
    linkconstraintlist::Vector{ConstraintRef}  #indices in JuMP model of linkconstraints for this edge
end
create_edge(graph::JuMPGraph) = JuMPEdge(BasePlasmoEdge(),ConstraintRef[])

#Construct a structured model, but roll it all into one JuMP model (this is how we solve with JuMP accessible solvers)
function JuMPGraphModel()
    m = JuMP.Model()
    m.ext[:Graph] = JuMPGraph()
    return m
end
is_graphmodel(m::JuMP.Model) = haskey(m.ext,:Graph) ? true : false  #check if the model is a graph model

# Should be defined by base type
# #Add nodes and edges to graph models.  These are used for model instantiation from a graph
function add_node!(m::JuMP.Model; index = nv(getgraph(m).basegraph)+1)
    is_graphmodel(m) || error("Can only add nodes to graph models")
    node = create_node(getgraph(m))
    add_node!(getgraph(m),node,index = index)
    return node
end

function add_edge!(m::Model,nodes::JuMPNode...)
    is_graphmodel(m) || error("Can only add edges to graph models")
    add_edge!(getgraph(m),nodes...)
    return edge
end

#Define all of the JuMP model extension functions
getgraph(m::Model) = haskey(m.ext, :Graph) ? m.ext[:Graph] : error("Model is not a graph model")
PlasmoGraphBase.getnodes(m::Model) = getnodes(getgraph(m))
getedges(m::Model) = getedges(getgraph(m))

getnode(m::Model,id::Integer) = getnode(getgraph(m),id)  #Grab from the highest level graph if not specified
getnode(m::Model,sid::Integer,nid::Integer) = getnode(getgraph(m).subgraphlist[sid],nid)

getedge(m::Model,id::LightGraphs.AbstractEdge) = getedge(getgraph(m))[id]
getedge(m::Model,sid::Integer,eid::LightGraphs.AbstractEdge) = getedge(getgraph(m).subgraphlist[sid],eid)

JuMP.getobjective(node::JuMPNode) = node.objective
JuMP.getobjectivevalue(node::JuMPNode) = getvalue(node.objective)

getnodevariablemap(node::JuMPNode) = node.variablemap
getnodevariables(node::JuMPNode) = node.variablelist
getnodevariable(node::JuMPNode,index::Integer) = node.variablelist[index]
getnodeconstraints(node::JuMPNode) = node.constraintlist
num_var(node::JuMPNode) = length(node.variablelist)

#get node variables
getindex(node::JuMPNode,s::Symbol) = node.variablemap[s]

#get all of the link constraints from a JuMP model
#Retrieves constraint indices that are link constraints
function getlinkconstraints(m::JuMP.Model)
    is_graphmodel(m) || error("link constraints are only available on graph models")
    return getgraph(m).linkconstraints
end

#Create a single JuMP model from a ModelGraph
@deprecate create_flat_graph_model create_jump_graph_model

function create_jump_graph_model(model_graph::AbstractModelGraph)
    jump_model = JuMPGraphModel()
    jump_graph = copy_graph(model_graph,to_graph_type = JuMPGraph)
    jump_model.ext[:Graph] = jump_graph

    #COPY NODE MODELS
    var_maps = Dict()
    for model_node in getnodes(model_graph)  #for each node in the model graph
        nodeindex = getindex(model_graph,model_node)
        jump_node = getnode(jump_graph,nodeindex)
        if hasmodel(model_node)
            m,var_map = _buildnodemodel!(jump_model,jump_node,model_node)
            var_maps[jump_node] = var_map
        end
    end

    #LINK CONSTRAINTS
    #inspect the link constraints, and map them to variables within flat model
    for linkconstraint in get_all_linkconstraints(model_graph)
        #linkconstraint = LinkConstraint(link)
        indexmap = Dict() #{node variable => new jump model variable index} Need index of node variables to flat model variables
        vars = linkconstraint.terms.vars
        for var in vars
            model_node = getnode(var)
            var_index = JuMP.linearindex(var)                   #index in modelgraph node
            node_index = getindex(model_graph,model_node)       #node index in modelgraph
            jump_node = getnode(jump_graph,node_index)          #the corresponding jumpgraph jumpnode
            flat_indexmap = jump_node.indexmap
            indexmap[var] = flat_indexmap[var_index]            #modelnode variable => jumpnode variable index
        end
        t = []
        for terms in linearterms(linkconstraint.terms)
            push!(t,terms)
        end
        con_reference = @constraint(jump_model, linkconstraint.lb <= sum(t[i][1]*JuMP.Variable(jump_model,indexmap[(t[i][2])]) for i = 1:length(t)) + linkconstraint.terms.constant <= linkconstraint.ub)
        push!(jump_graph.linkconstraints,con_reference)
    end

    #OBJECTIVE
    #sum the objectives by default
    has_nonlinear_obj = false   #check if any nodes have nonlinear objectives
    for node in getnodes(model_graph)
        node_model = getmodel(node)
        nlp = node_model.nlpdata
        if nlp != nothing && nlp.nlobj != nothing
            has_nonlinear_obj = true
            break
        end
    end

    if has_nonlinear_obj  == false      #just sum linear or quadtratic objectives
        @objective(jump_model,Min,sum(getobjective(node) for node in getnodes(jump_graph)))

    elseif has_nonlinear_obj == true  #build up the objective expression and splice in variables.  Cast all objectives as nonlinear
        obj = :(0)
        #for (id,node) in getnodesandedges(flat_graph)
        for node in getnodes(jump_graph)
            id = getindex(jump_graph,node)
            node_model = getmodel(getnode(model_graph,id))
            getobjectivesense(node_model) == :Min ? sense = 1 : sense = -1
            nlp = node_model.nlpdata
            if nlp == nothing# || (nlp != nothing && nlp.nlobj == nothing) #cast the problem as nonlinear
                #copy_model = copy(node_model)
                d = JuMP.NLPEvaluator(node_model)

                MathProgBase.initialize(d,[:ExprGraph])
                node_obj = MathProgBase.obj_expr(d)
                _splicevars!(node_obj,var_maps[node])
                JuMP.ProblemTraits(node_model).nlp = false
                node_model.nlpdata = nothing
            elseif  nlp != nothing# && nlp.nlobj == nothing
                d = JuMP.NLPEvaluator(node_model)
                #@objective(copy_model,Min,0)  #have to clear the objective here to get this to work
                MathProgBase.initialize(d,[:ExprGraph])
                node_obj = MathProgBase.obj_expr(d)
                _splicevars!(node_obj,var_maps[node])
            end
            #node_obj = getnodeobjective(node)
            node_obj = Expr(:call,:*,:($sense),node_obj)
            obj = Expr(:call,:+,obj,node_obj)
        end
        #println(obj)
        JuMP.setNLobjective(jump_model, :Min, obj)
    end
    return jump_model
end

#Function to build a node model for a flat graph model
function _buildnodemodel!(m::Model,jump_node::JuMPNode,model_node::ModelNode)
    node_model = getmodel(model_node)

    num_vars = MathProgBase.numvar(node_model)
    var_map = Dict()              #this dict will map linear index of the node model variables to the new model JuMP variables {node var index => flat model JuMP.Variable}
    node_map = Dict()             #nodemap. {varkey => [var1,var2,...]}
    index_map = Dict()            #{var index in node => var index in flat model}

    #add the node model variables to the new model
    for i = 1:num_vars
        x = JuMP.@variable(m)                                                #create an anonymous variable
        setlowerbound(x,node_model.colLower[i])
        setupperbound(x,node_model.colUpper[i])
        var_name = string(Variable(node_model,i))
        new_name = "$(getlabel(jump_node))$(getindex(getgraph(m),jump_node))."*var_name
        setname(x,new_name)                                                  #rename the variable to the node model variable name plus the node or edge name
        setcategory(x,node_model.colCat[i])                                  #set the variable to the same category
        setvalue(x,node_model.colVal[i])                                     #set the variable to the same value
        var_map[i] = x                                                       #map the linear index of the model_node variable to the new variable in the jump_node
        index_map[i] = linearindex(x)                                        #map of jump node variable index to it's actual flat model index
        m.objDict[Symbol(new_name)] = x                                      #Update master model variable dictionary
        push!(jump_node.variablelist,x)
    end
    #setup the node_map dictionary.  This maps the node model's variable keys to variables in the newly constructed model.

    #TODO Create an objdict with the reproduced JuMP container types for each node
    for key in keys(node_model.objDict)  #this contains both variable and constraint references
        if isa(node_model.objDict[key],Union{JuMP.JuMPArray{AbstractJuMPScalar},Array{AbstractJuMPScalar}})     #if the JuMP variable is an array or a JuMPArray
            vars = node_model.objDict[key]
            isa(vars,JuMP.JuMPArray) ? vars = vars.innerArray : nothing
            dims = JuMP.size(vars)
            node_map[key] = Array{AbstractJuMPScalar}(dims)
            for j = 1:length(vars)
                var = vars[j]
                node_map[key][j] = var_map[linearindex(var)]
            end
        #reproduce the same mapping in a dictionary
        elseif isa(node_model.objDict[key],JuMP.JuMPDict)
            tdict = node_model.objDict[key].tupledict  #get the tupledict
            d_tmp = Dict()
            for dkey in keys(tdict)
                d_tmp[dkey] = var_map[linearindex(tdict[dkey])]
            end
            node_map[key] = d_tmp

        elseif isa(node_model.objDict[key],JuMP.AbstractJuMPScalar) #else it's a single variable
            node_map[key] = var_map[linearindex(node_model.objDict[key])]
        # else #objDict also has contraints!
        #     error("Did not recognize the type of a JuMP variable $(node_model.objDict[key])")
        end
    end

    jump_node.variablemap = node_map
    jump_node.indexmap = index_map

    #COPY LINEAR CONSTRAINTS
    for i = 1:length(node_model.linconstr)
        con = node_model.linconstr[i]
        #t = collect(linearterms(con.terms))  #This is broken in julia 0.5
        t = []
        for terms in linearterms(con.terms)
            push!(t,terms)
        end
        reference = @constraint(m, con.lb <= sum(t[i][1]*var_map[linearindex(t[i][2])] for i = 1:length(t)) + con.terms.constant <= con.ub)
        # push!(getattribute(nodeoredge,:NodeData).constraintlist,reference)
        push!(jump_node.constraintlist,reference)
    end

    #COPY QUADRATIC CONSTRAINTS
    for i = 1:length(node_model.quadconstr)
        con = node_model.quadconstr[i]
        #collect the linear terms
        t = []
        for terms in linearterms(con.terms.aff)
            push!(t,terms)
        end
        qcoeffs =con.terms.qcoeffs
        qvars1 = con.terms.qvars1
        qvars2 = con.terms.qvars2
        #Might be a better way to do this
        if con.sense == :(==)
            reference = @constraint(m,sum(qcoeffs[i]*var_map[linearindex(qvars1[i])]*var_map[linearindex(qvars2[i])] for i = 1:length(qcoeffs)) +
            sum(t[i][1]*var_map[linearindex(t[i][2])] for i = 1:length(t)) + con.terms.aff.constant == 0)
        elseif con.sense == :(<=)
            reference = @constraint(m,sum(qcoeffs[i]*var_map[linearindex(qvars1[i])]*var_map[linearindex(qvars2[i])] for i = 1:length(qcoeffs)) +
            sum(t[i][1]*var_map[linearindex(t[i][2])] for i = 1:length(t)) + con.terms.aff.constant <= 0)
        elseif con.sense == :(>=)
            reference = @constraint(m,sum(qcoeffs[i]*var_map[linearindex(qvars1[i])]*var_map[linearindex(qvars2[i])] for i = 1:length(qcoeffs)) +
            sum(t[i][1]*var_map[linearindex(t[i][2])] for i = 1:length(t)) + con.terms.aff.constant >= 0)
        end
        # push!(getattribute(nodeoredge,:NodeData).constraintlist,reference)
        push!(jump_node.constraintlist,reference)
    end

    #COPY NONLINEAR CONSTRAINTS
    if JuMP.ProblemTraits(node_model).nlp == true   #If it's a NLP
        d = JuMP.NLPEvaluator(node_model)           #Get the NLP evaluator object.  Initialize the expression graph
        MathProgBase.initialize(d,[:ExprGraph])
        num_cons = MathProgBase.numconstr(node_model)
        start_index = length(node_model.linconstr) + length(node_model.quadconstr) + 1 # the start index for nonlinear constraints
        for i = start_index:num_cons
            #if !(MathProgBase.isconstrlinear(d,i))    #if it's not a linear constraint
            expr = MathProgBase.constr_expr(d,i)  #this returns a julia expression
            _splicevars!(expr,var_map)              #splice the variables from var_map into the expression
            con = JuMP.addNLconstraint(m,expr)    #raw expression input for non-linear constraint
            # push!(getattribute(nodeoredge,:NodeData).constraintlist,con)  #Add the nonlinear constraint reference to the node
            #push!(nodeoredge.node_data.constraintlist,con)  #Add the nonlinear constraint reference to the node
            push!(jump_node.constraintlist,con)
            #end
        end
    end

    #OBJECTIVE FUNCTION
    getobjectivesense(node_model) == :Min ? sense = 1 : sense = -1

    #LINEAR OR QUADRATIC OBJECTIVE
    nlp = node_model.nlpdata
    if nlp == nothing  || (nlp !== nothing && nlp.nlobj == nothing)
        #Get the linear terms
        t = []
        for terms in linearterms(node_model.obj.aff)
            push!(t,terms)
        end
        #Get the quadratic terms
        qcoeffs = node_model.obj.qcoeffs
        qvars1 = node_model.obj.qvars1
        qvars2 = node_model.obj.qvars2
        obj = @objective(m,Min,sense*(sum(qcoeffs[i]*var_map[linearindex(qvars1[i])]*var_map[linearindex(qvars2[i])] for i = 1:length(qcoeffs)) +
        sum(t[i][1]*var_map[linearindex(t[i][2])] for i = 1:length(t)) + node_model.obj.aff.constant))
        jump_node.objective = m.obj

    #NONLINEAR OBJECTIVE
    elseif nlp != nothing && nlp.nlobj != nothing
        obj = MathProgBase.obj_expr(d)
        _splicevars!(obj,var_map)
        obj = Expr(:call,:*,:($sense),obj)
        jump_node.objective = m.obj
    end
    return m,var_map
end

#splice variables into a constraint expression
function _splicevars!(expr::Expr,var_map::Dict)
    for i = 1:length(expr.args)
        if typeof(expr.args[i]) == Expr
            if expr.args[i].head != :ref   #keep calling _splicevars! on the expression until it's a :ref. i.e. :(x[index])
                _splicevars!(expr.args[i],var_map)
            else  #it's a variable
                var_index = expr.args[i].args[2]     #this is the actual index in x[1], x[2], etc...
                new_var = :($(var_map[var_index]))   #get the JuMP variable from var_map using the index
                expr.args[i] = new_var               #replace :(x[index]) with a :(JuMP.Variable)
            end
        end
    end
end

#Create a JuMP model and solve with a MPB compliant solver
buildjumpmodel!(graph::AbstractModelGraph) = graph.serial_model = create_jump_graph_model(graph)
function jump_solve(graph::AbstractModelGraph;scale = 1.0,kwargs...)
    println("Aggregating Models...")
    m_flat = buildjumpmodel!(graph)
    println("Finished Creating JuMP Model")
    m_flat.solver = graph.linkmodel.solver
    m_flat.obj = scale*m_flat.obj
    status = JuMP.solve(m_flat;kwargs...)
    if status == :Optimal
        setsolution(getgraph(m_flat),graph)                       #Now get our solution data back into the original ModelGraph
        _setobjectivevalue(graph,JuMP.getobjectivevalue(m_flat))  #Set the graph objective value for easy access
    end
    return status
end

#check if graph has a mathprogbase solver
function JuMP.solve(graph::AbstractModelGraph;scale = 1.0,kwargs...)
    if isa(getsolver(graph),AbstractMathProgSolver)
        status = jump_solve(graph,scale = scale,kwargs...)
    elseif isa(getsolver(graph),AbstractPlasmoSolver)
        status = solve(graph,getsolver(graph))
    else
        throw(error("Given solver not recognized"))
    end
    return status
end

#define some setvalue functions for convenience when dealing with JuMP JuMPArray type
#dimension of jarr2 must be greater than jarr1
function setarrayvalue(jarr1::JuMP.JuMPArray,jarr2::JuMP.JuMPArray)# = setvalue(jarr1.innerArray,jarr2.innerArray)
    for i = 1:length(jarr2.innerArray)
        JuMP.setvalue(jarr1[i],jarr2[i])
    end
end

function setarrayvalue(jarr1::Array,jarr2::Array)# = setvalue(jarr1.innerArray,jarr2.innerArray)
    for i = 1:length(jarr2)
        JuMP.setvalue(jarr1[i],jarr2[i])
    end
end

function setarrayvalue(jarr1::JuMP.JuMPArray,jarr2::Array) # = setvalue(jarr1.innerArray,jarr2)
    for i = 1:length(jarr2)
        JuMP.setvalue(jarr1.innerArray[i],jarr2[i])
    end
end

function setarrayvalue(jarr1::Array,jarr2::JuMP.JuMPArray) # = setvalue(jarr1,jarr2.innerArray)
    for i = 1:length(jarr2)
        JuMP.setvalue(jarr1[i],jarr2.innerArray[i])
    end
end

#define some getvalue and setvalue functions for dealing with JuMPDict objects.
function setvalue(dict::Dict,jdict::JuMP.JuMPDict)
    for key in keys(dict)
        jdict.tupledict[key] = dict[key]
    end
end

function setvalue(jdict::JuMP.JuMPDict,dict::Dict)
    for key in keys(jdict.tupledict)
        dict[key] = jdict.tupledict[key]
    end
end

#copy the solution from one graph to another where nodes and variables match
function setsolution(graph1::AbstractModelGraph,graph2::AbstractModelGraph)
    for node in getnodes(graph1)
        index = getindex(graph1,node)
        node2 = getnode(graph2,index)       #get the corresponding node or edge in graph2
        for i = 1:num_var(node)
            node1_var = getnodevariable(node,i)
            node2_var = getnodevariable(node2,i)
            setvalue(node2_var,getvalue(node1_var))
        end
    end
    #TODO Set dual values for linear constraints
end


#TODO
# function setsumgraphobjectives(graph)
#     has_nonlinear = false
#     #check if any nodes have nonlinear objectives
#     for node in getnodesandedges(graph)
#         node_model = getmodel(node)
#         traits = JuMP.ProblemTraints(node_model)
#         if traits.nlp == true
#             has_nonlinear = true
#             break
#         end
#     end
#     #if it's all linear or quadtratic
#     if has_nonlinear  == false
#         obj = 0
#         for node in getnodesandedges(graph)
#             node_model = getmodel(node)
#             obj += node_model.obj
#         end
#         graph.obj = obj  #set the graph objective to the sum of each node
#     elseif has_nonlinear == true
#         obj = :()
#         for node in getnodesandedges(graph)
#             node_model = getmodel(node)
#             d = JuMP.NLPEvaluator(node_model)
#             MathProgBase.initialize(d,[:ExprGraph])
#             node_obj = MathProgBase.obj_expr(d)
#             obj = Expr(:call,:+,copy(obj),node_obj)
#             # ex1 = MathProgBase.obj_expr(d)
#             # ex2 = MathProgBase.obj_expr(d2)
#             # newexpr = Expr(:call, :+, copy(ex1), copy(ex2))
#             # JuMP.setNLobjective(m, P.objSense, newexpr)
#         end
#     end
# end

# for (key,var) in getnodevariablemap(node)
#     var2 = node2[key]
#     if isa(var,JuMP.JuMPArray) || isa(var,Array)# || isa(var,JuMP.Variable)
#         vals = JuMP.getvalue(var)  #get value of the
#         Plasmo.setarrayvalue(var2,vals)  #the dimensions have to line up for arrays
#     elseif isa(var,JuMP.JuMPDict) || isa(var,Dict)
#         Plasmo.setvalue(var,var2)
#     elseif isa(var,JuMP.Variable)
#         JuMP.setvalue(var2,JuMP.getvalue(var))
#     else
#         error("encountered a variable type not recognized")
#     end
# end

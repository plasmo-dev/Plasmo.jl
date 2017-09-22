#This file contains all of the constructs to create and manage a JuMP GraphModel.  The idea is that you use PLASMO to create your graph, associate models, and build the
#flattened model which JuMP can always solve in serial.

import JuMP:AbstractModel,Model,Variable,ConstraintRef,getvariable,@variable,@constraint,@objective,GenericQuadExpr,GenericAffExpr,solve,setvalue,getvalue
import MathProgBase

#typealias GenericExpr Union{GenericQuadExpr,GenericAffExpr} #NonlinearExpression?
type NodeData
    objective#::GenericExpr                      #Individual objective expression....    #Need the nlp evaluator with the Expr graph to do this?
    variablemap::Dict{Symbol,Any}                #Dictionary of symbols to Model variables
    constraintlist::Vector{ConstraintRef}        #Vector of model constraints (make this a dictionary too)
    indexmap::Dict{Int,Int}                      #linear index of node variable in flat model to the original index of the component model
end
NodeData() = NodeData(0,Dict{Symbol,Any}(),ConstraintRef[],Dict{Int,Int}())

type JuMPGraph <: AbstractPlasmoGraph end

type JuMPNode <: AbstractNode
    index::Dict{AbstractPlasmoGraph,Int} #map to an index in each graph containing the node
    label::Symbol
    attributes::Dict{Any,Any}
    node_data::NodeData
end

type JuMPEdge <: AbstractEdge
    index::Dict{AbstractPlasmoGraph,LightGraphs.Edge} #map to an index in each graph containing the node
    label::Symbol
    attributes::Dict{Any,Any}
    node_data::NodeData
end

const JuMPNodeOrEdge = Union{JuMPNode,JuMPEdge}
hasmodel(nodeoredge::JuMPNodeOrEdge) = false
#Construct a structured model, but roll it all into one JuMP model (this is how we solve with JuMP accessible solvers)
function FlatGraphModel()
    m = JuMP.Model()
    m.ext[:Graph] = Plasmo.PlasmoGraph()
    return m
end

is_graphmodel(m::Model) = haskey(m.ext,:Graph)? true : false  #check if the model is a graph model

#Add nodes and edges to graph models.  These are used for model instantiation from a graph
function add_node!(m::Model; index = nv(getgraph(m).graph)+1)
    is_graphmodel(m) || error("Can only add nodes to graph models")
    @assert is_graphmodel(m)
    node = JuMPNode(Dict{AbstractPlasmoGraph,Int}(), Symbol("node"),Dict(),NodeData())
    add_node!(getgraph(m),node,index = index)
    return node
end

function add_edge!(m::Model,node1::JuMPNode,node2::JuMPNode)
    is_graphmodel(m) || error("Can only add nodes to graph models")
    @assert is_graphmodel(m)
    edge = JuMPEdge(Dict{AbstractPlasmoGraph,Edge}(), Symbol("edge"),Dict{Any,Any}(),NodeData())
    add_edge!(getgraph(m),edge,node1,node2)
    return edge
end

#Define all of the PlasmoGraph functions for a GraphModel
getgraph(m::Model) = haskey(m.ext, :Graph)? m.ext[:Graph] : error("Model is not a graph model")
getnodes(m::Model) = getnodes(getgraph(m))
getedges(m::Model) = getedges(getgraph(m))

#TODO
#Need to account for which graph to get from
getnode(m::Model,id::Integer) = getnodes(getgraph(m))[id]
getedge(m::Model,id::LightGraphs.Edge) = getedges(getgraph(m))[id]
#write node constraints, edge constraints, and coupling constraints
# getnodedata(nodeoredge::NodeOrEdge) = getattribute(nodeoredge,:NodeData)
getnodedata(nodeoredge::JuMPNodeOrEdge) = nodeoredge.node_data
getnodeobjective(nodeoredge::JuMPNodeOrEdge) = nodeoredge.node_data.objective
getnodeobjective(nodeoredge::NodeOrEdge) = JuMP.getobjective(nodeoredge.model)


getnodevariables(nodeoredge::JuMPNodeOrEdge) =  nodeoredge.node_data.variablemap
#TODO This is dangerous.  objDict contains constraints
getnodevariables(nodeoredge::NodeOrEdge) = getmodel(nodeoredge).objDict
getnodeconstraints(nodeoredge::JuMPNodeOrEdge) = nodeoredge.node_data.constraintlist

getindex(nodeoredge::JuMPNodeOrEdge,s::Symbol) = nodeoredge.node_data.variablemap[s]  #get a node or edge variable
getindex(nodeoredge::NodeOrEdge,s::Symbol) = getmodel(nodeoredge)[s]

#get all of the link constraints from a JuMP model
function getlinkconstraints(m::JuMP.Model)
    is_graphmodel(m) || error("link constraints are only available on graph models")
    @assert is_graphmodel(m)
    cons = Dict()
    for nodeoredge in getnodes(getgraph(m))
        push!(cons,getlinkconstraints(node))
    end
    return cons
end

#Create a single JuMP model from a plasmo graph
function create_flat_graph_model(graph::PlasmoGraph)
    flat_model = FlatGraphModel()
    flat_graph = getgraph(flat_model)
    #copy number of subgraphs (might need recursive function here!)
    _copy_subgraphs!(graph,flat_graph)
    #first copy all nodes, then setup all the subgraphs
    var_maps = Dict()
    #COPY NODE MODELS
    for (index,node) in getnodes(graph)
        new_node = add_node!(flat_model,index = index)  #create the node and add a vertex to the top level graph.  We pass the index explicity for this graph
        node_index = getindex(node) #returns dict of {graph => index}

        for igraph in keys(node_index)       #For each subgraph this node is contained in....
            if igraph.index != 0             #if it's not the top level graph
                graph_index = igraph.index   #the index of this subgraph
                subgraph = flat_graph.subgraphlist[graph_index]  #the flat_model subgraph
                add_node!(subgraph,new_node,index = node.index[igraph])
                #add_node!(subgraph,new_node,index = node.index[igraph.subgraphlist[graph_index]])  #should be index of the node within igraph (the subgraph)
            end
        end
        if hasmodel(node)
            node_model = getmodel(node)
            m,var_map = _buildnodemodel!(flat_model,new_node,node_model)
            var_maps[new_node] = var_map
        end
    end

    #COPY EDGE MODLES
    for (index,edge) in getedges(graph)
        pair = getindex(graph,edge)
        new_nodes = getsupportingnodes(flat_graph,pair)
        new_edge = add_edge!(flat_model,new_nodes[1],new_nodes[2])
        #new_edge.index[flat_graph] = index
        for igraph in keys(edge.index)
            if igraph.index != 0
                index = igraph.index
                subgraph = flat_graph.subgraphlist[index]
                pair = getindex(igraph.subgraphlist[index],new_edge)
                add_edge!(subgraph,pair)
            end
        end

        if hasmodel(edge)
            edge_model = getmodel(edge)
            m,var_map = _buildnodemodel!(flat_model,new_edge,edge_model)
            var_maps[new_edge] = var_map
        end
    end

    #LINK CONSTRAINTS
    #inspect the link constraints, and map them to variables within flat model
    for linkconstraint in get_all_linkconstraints(graph)
        indexmap = Dict() #{node variable => flat variable index} Need index of node variables to flat model variables
        vars = linkconstraint.terms.vars
        for var in vars
            nodeoredge = getnode(var)
            var_index = JuMP.linearindex(var)
            node_index = getindex(graph,nodeoredge)                 #node index in graph.  This could be a problem with edges and subgraphs
            flat_nodeoredge = getnodeoredge(flat_graph,node_index)  #should be the corresponding node
            flat_indexmap = getnodedata(flat_nodeoredge).indexmap
            indexmap[var] = flat_indexmap[var_index]
        end
        t = []
        for terms in linearterms(linkconstraint.terms)
            push!(t,terms)
        end
        con_reference = @constraint(flat_model, linkconstraint.lb <= sum(t[i][1]*JuMP.Variable(flat_model,indexmap[(t[i][2])]) for i = 1:length(t)) + linkconstraint.terms.constant <= linkconstraint.ub)
    end

    #OBJECTIVE
    #sum the objectives by default
    has_nonlinear_obj = false   #check if any nodes have nonlinear objectives
    for (id,node) in getnodesandedges(graph)
        node_model = getmodel(node)
        nlp = node_model.nlpdata
        if nlp != nothing && nlp.nlobj != nothing
            has_nonlinear_obj = true
            break
        end
    end

    if has_nonlinear_obj  == false #just sum linear or quadtratic objectives
        @objective(flat_model,Min,sum(getnodeobjective(nodeoredge) for nodeoredge in values(getnodesandedges(flat_graph))))

    elseif has_nonlinear_obj == true  #build up the objective expression and splice in variables.  Cast all objectives as nonlinear
        obj = :(0)

        for (id,node) in getnodesandedges(flat_graph)
            node_model = getmodel(getnode(graph,id))
            getobjectivesense(node_model) == :Min? sense = 1: sense = -1
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
        JuMP.setNLobjective(flat_model, :Min, obj)
    end
    return flat_model
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

#Function to build a node model for a flat graph model
function _buildnodemodel!(m::Model,nodeoredge::NodeOrEdge,node_model::Model)
    #@assert nodeoredge in [getgraph(m).nodes;getgraph(m).edges]
    num_vars = MathProgBase.numvar(node_model)
    var_map = Dict()              #this dict will map linear index of the node model variables to the new model JuMP variables {node var index => flat model JuMP.Variable}
    node_map = Dict()             #nodemap. {varkey => [var1,var2,...]}
    index_map = Dict()            #{var index in node => var index in flat model}

    #add the node model variables to the new model
    for i = 1:num_vars
        x = JuMP.@variable(m)            #create an anonymous variable
        setlowerbound(x,node_model.colLower[i])
        setupperbound(x,node_model.colUpper[i])
        var_name = string(Variable(node_model,i))
        new_name = "$(nodeoredge.label)$(nodeoredge.index[getgraph(m)])."*var_name
        setname(x,new_name)       #rename the variable to the node model variable name plus the node or edge name
        setcategory(x,node_model.colCat[i])                                  #set the variable to the same category
        setvalue(x,node_model.colVal[i])                                     #set the variable to the same value
        var_map[i] = x                                                       #map the linear index of the node model variable to the new variable
        index_map[i] = linearindex(x)
        m.objDict[Symbol(new_name)] = x #Update master model variable dictionary
    end
    #setup the node_map dictionary.  This maps the node model's variable keys to variables in the newly constructed model.

    #TODO Reconstruct the appropriate JuMP containers (Need to figure out how to actually construct these)
    for key in keys(node_model.objDict)  #this contains both variable and constraint references
        if isa(node_model.objDict[key],Union{JuMP.JuMPArray{Variable},Array{Variable}})     #if the JuMP variable is an array or a JuMPArray
            vars = node_model.objDict[key]
            isa(vars,JuMP.JuMPArray)? vars = vars.innerArray : nothing
            dims = JuMP.size(vars)
            node_map[key] = Array{JuMP.Variable}(dims)
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

        elseif isa(node_model.objDict[key],JuMP.Variable) #else it's a single variable
            node_map[key] = var_map[linearindex(node_model.objDict[key])]
            #node_map[key] = var_map[node_model.objDict[key].col]

        # else #objDict also has contraints!
        #     error("Did not recognize the type of a JuMP variable $(node_model.objDict[key])")
        end
    end
    # getattribute(nodeoredge,:NodeData).variablemap = node_map
    # getattribute(nodeoredge,:NodeData).indexmap = index_map
    nodeoredge.node_data.variablemap = node_map
    nodeoredge.node_data.indexmap = index_map

    #copy the linear constraints to the new model
    for i = 1:length(node_model.linconstr)
        con = node_model.linconstr[i]
        #t = collect(linearterms(con.terms))  #This is broken in julia 0.5
        t = []
        for terms in linearterms(con.terms)
            push!(t,terms)
        end
        reference = @constraint(m, con.lb <= sum(t[i][1]*var_map[linearindex(t[i][2])] for i = 1:length(t)) + con.terms.constant <= con.ub)
        # push!(getattribute(nodeoredge,:NodeData).constraintlist,reference)
         push!(nodeoredge.node_data.constraintlist,reference)
    end

    #copy the quadratic constraints to the new model
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
        push!(nodeoredge.node_data.constraintlist,reference)
    end

    getobjectivesense(node_model) == :Min? sense = 1: sense = -1
    #Copy the non-linear constraints to the new model
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
            push!(nodeoredge.node_data.constraintlist,con)  #Add the nonlinear constraint reference to the node
            #end
        end
        #Also check for nonlinear objective here
        # #TODO Find way to add nonlinear objectives together
        # if node_model.nlpdata.nlobj != nothing
        #     warn("Plasmo does not yet support aggregating nonlinear objectives")
    end

    #If the objective is linear
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
        #getattribute(nodeoredge,:NodeData).objective = m.obj
        nodeoredge.node_data.objective = m.obj
    #If the objective is nonlinear
    elseif nlp != nothing && nlp.nlobj != nothing
        obj = MathProgBase.obj_expr(d)
        _splicevars!(obj,var_map)
        obj = Expr(:call,:*,:($sense),obj)
        nodeoredge.node_data.objective = obj
        #getattribute(nodeoredge,:NodeData).objective = obj
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
function setsolution(graph1::AbstractPlasmoGraph,graph2::AbstractPlasmoGraph)
    for (index,nodeoredge) in getnodesandedges(graph1)
        nodeoredge2 = getnodeoredge(graph2,index)       #get the corresponding node or edge in graph2
        for (key,var) in getnodevariables(nodeoredge)
            var2 = nodeoredge2[key]
            if isa(var,JuMP.JuMPArray) || isa(var,Array)# || isa(var,JuMP.Variable)
                vals = JuMP.getvalue(var)  #get value of the
                Plasmo.setarrayvalue(var2,vals)  #the dimensions have to line up for arrays
            elseif isa(var,JuMP.JuMPDict) || isa(var,Dict)
                Plasmo.setvalue(var,var2)
            elseif isa(var,JuMP.Variable)
                JuMP.setvalue(var2,JuMP.getvalue(var))
            else
                error("encountered a variable type not recognized")
            end
        end
        #TODO Also set the node objectives
        if hasmodel(nodeoredge2)
            m = getmodel(nodeoredge2)
            m.objVal = getvalue(m.obj)
        end
    end
end

buildserialmodel(graph::PlasmoGraph) = graph.internal_serial_model =  create_flat_graph_model(graph)
function solve(graph::PlasmoGraph;kwargs...)
    println("Aggregating Models...")
    m_flat = create_flat_graph_model(graph)
    graph.internal_serial_model = m_flat
    println("Finished model instantiation")
    m_flat.solver = graph.solver
    status = JuMP.solve(m_flat,kwargs...)
    if status == :Optimal
        setsolution(getgraph(m_flat),graph)           #Now get our solution data back into the original model
        _setobjectivevalue(graph,JuMP.getobjectivevalue(m_flat))  #Set the graph objective value for easy access
    end
    return status
end

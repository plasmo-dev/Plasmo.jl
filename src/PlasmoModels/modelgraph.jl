import ..PlasmoGraphBase:add_node!,add_edge!,create_node,create_edge,getnode,getnodes
import Base:show,print,string,getindex,copy
import JuMP:AbstractModel,setobjective,getobjectivevalue,setsolver,getvalue
import LightGraphs.Graph
import MathProgBase.numvar


##############################################################################
# ModelGraph
##############################################################################
#A PlasmoGraph encapsulates a pure graph object wherein nodes and edges are integers and pairs of integers respectively
"The ModelGraph Type.  Represents a system of models and the links between them"
mutable struct ModelGraph <: AbstractModelGraph
    basegraph::BasePlasmoGraph                   #model structure.  Put constraint references on edges
    linkmodel::LinkModel                         #Using composition to represent a graph as a "Model".  Someday I will figure out how to do multiple inheritance.
    serial_model::Nullable{AbstractModel}        #The internal serial model for the graph.  Returned if requested by the solve
end

ModelGraph() = ModelGraph(BasePlasmoGraph(HyperGraph),LinkModel(),Nullable())
@deprecate PlasmoGraph ModelGraph
@deprecate GraphModel ModelGraph
#ModelGraph(lightgraph::LightGraphs.AbstractGraph) = ModelGraph(BasePlasmoGraph(HyperGraph),LinkModel(),Nullable())
#ModelGraph() = ModelGraph(BasePlasmoGraph(Graph),LinkModel(),Nullable())

#Write total objective functions for a model graph
setobjective(graph::ModelGraph, sense::Symbol, x::JuMP.Variable) = setobjective(graph.linkmodel, sense, convert(AffExpr,x))

getlinkconstraints(model::ModelGraph) = getlinkconstraints(model.linkmodel)
getsimplelinkconstraints(model::ModelGraph) = getsimplelinkconstraints(model.linkmodel)
gethyperlinkconstraints(model::ModelGraph) = gethyperlinkconstraints(model.linkmodel)

_setobjectivevalue(graph::ModelGraph,value::Number) = graph.linkmodel.objval = value
JuMP.getobjectivevalue(graph::ModelGraph) = graph.linkmodel.objval

getinternaljumpmodel(graph::ModelGraph) = get(graph.serial_model)

"""
    Get every link constraint in the graph, including subgraphs
"""
function get_all_linkconstraints(graph::ModelGraph)
    links = []
    for subgraph in getsubgraphlist(graph)
        append!(links,getlinkconstraints(subgraph))
    end
    append!(links,getlinkconstraints(graph))
    return links
end

#TODO Figure out how JuMP sets solvers with MOI
setsolver(model::ModelGraph,solver::AbstractMathProgSolver) = model.linkmodel.solver = solver

##############################################################################
# Nodes
##############################################################################
mutable struct ModelNode <: AbstractModelNode
    basenode::BasePlasmoNode
    model::Nullable{AbstractModel}
    linkconrefs::Dict{ModelGraph,Vector{ConstraintRef}}
end
@deprecate NodeOrEdge ModelNode
#Node constructors
#empty PlasmoNode
ModelNode() = ModelNode(BasePlasmoNode(),JuMP.Model(),Dict{ModelGraph,Vector{ConstraintRef}}())
create_node(graph::ModelGraph) = ModelNode()

getmodel(node::ModelNode) = get(node.model)
hasmodel(node::ModelNode) = get(node.model) != nothing? true: false

#Get all of the link constraints for a node in all of its graphs
getlinkreferences(node::ModelNode) = node.linkconrefs
getlinkreferences(graph::ModelGraph,node::ModelNode) = node.linkconrefs[graph]
#Link constraints SHOULD be unique to each graph
function getlinkconstraints(node::ModelNode)
    links = Dict()
    for (graph,refs) in node.linkconrefs
        links[graph] = Vector{LinkConstraint}()
        for ref in refs
            push!(links[graph],LinkConstraint(ref))
        end
    end
    return links
end

function getlinkconstraints(graph::ModelGraph,node::ModelNode)
    links = []
    for ref in node.linkconrefs[graph]
        push!(links,LinkConstraint(ref))
    end
    return links
end

is_nodevar(node::ModelNode,var::AbstractJuMPScalar) = getmodel(node) == var.m #checks whether a variable belongs to a node or edge
_is_assignedtonode(m::AbstractModel) = haskey(m.ext,:node) #check whether a model is assigned to a node

getnode(m::AbstractModel) = _is_assignedtonode(m)? m.ext[:node] : throw(error("Only node models have associated graph nodes"))
getnode(var::AbstractJuMPScalar) = var.m.ext[:node]

num_var(node::ModelNode) = MathProgBase.numvar(getmodel(node))

#get variable index on a node
getindex(node::ModelNode,sym::Symbol) = getmodel(node)[sym]

function setmodel(node::ModelNode,m::AbstractModel;preserve_links = false)
    #_updatelinks(m,nodeoredge)      #update link constraints after setting a model
    !(_is_assignedtonode(m) && getmodel(node) == m) || error("the model is already asigned to another node")
    #TODO
    #BREAK LINKS FOR NOW
    # If it already had a model, delete all the link constraints corresponding to that model
    # if hasmodel(node)
    #     for (graph,constraints) in getlinkconstraints(node)
    #         local_link_cons = constraints
    #         graph_links = getlinkconstraints(graph)
    #         filter!(c -> !(c in local_link_cons), graph_links)  #filter out local link constraints
    #         node.link_data = NodeLinkData()   #reset the local node or edge link data
    #     end
    # end
    node.model = m
    m.ext[:node] = node
end
const setmodel! = setmodel


#TODO
#set a model with the same variable names and dimensions as the old model on the node.
#This will not break link constraints
function resetmodel(node::ModelNode,m::AbstractModel)
    #reassign the model
    node.model = m

    #switch out variables in any connected linkconstraints
    #throw warnings if link constraints break
end

JuMP.getobjective(node::ModelNode) = getobjective(node.model)
JuMP.getobjectivevalue(node::ModelNode) = getobjectivevalue(node.model)
setobjectivevalue(node::ModelNode,num::Number) = getmodel(node).objVal = num

@deprecate getgraphobjectivevalue getobjectivevalue
#TODO?
# removemodel(nodeoredge::NodeOrEdge) = nodeoredge.attributes[:model] = nothing  #need to update link constraints

##############################################################################
# Edges
##############################################################################
struct LinkingEdge <: AbstractLinkingEdge
    baseedge::BasePlasmoEdge
    linkconrefs::Vector{ConstraintRef}
end
#Edge constructors
LinkingEdge() = LinkingEdge(BasePlasmoEdge(),JuMP.ConstraintRef[])
create_edge(graph::ModelGraph) = LinkingEdge()

function add_edge!(graph::ModelGraph,ref::JuMP.ConstraintRef)
    con = LinkConstraint(ref)   #Get the Linkconstraint object so we can inspect the nodes on it
    vars = con.terms.vars
    nodes = unique([getnode(var) for var in vars])  #each var belongs to a node
    edge = add_edge!(graph,nodes...)  #constraint edge connected to more than 2 nodes
    push!(edge.linkconrefs,ref)
    for node in nodes
        if !haskey(node.linkconrefs,graph)
            node.linkconrefs[graph] = [ref]
        else
            push!(node.linkconrefs[graph],ref)
        end
    end
    return edge
end

# TODO  Think of a good way to update links when swapping out models.  Might need to store variable names in NodeLinkData
# function _updatelinks(m,::AbstractModel,nodeoredge::NodeOrEdge)
#     link_cons = getlinkconstraints(nodeoredge)
#     #find variables
# end

########################################
#Other add_node! constructors
#######################################
#Add nodes and set the model as well
function add_node!(graph::ModelGraph,m::AbstractModel)
    node = add_node!(graph)
    setmodel!(node,m)
    return node
end

########################################
# Add the link constraints
########################################
#Store link constraint in the given graph.  Store a reference to the linking constraint on the nodes which it links
function addlinkconstraint(graph::ModelGraph,con::AbstractConstraint)
    isa(con,JuMP.LinearConstraint) || throw(error("Link constraints must be linear.  If you're trying to add quadtratic or nonlinear links, try creating duplicate variables and linking those"))
    ref = JuMP.addconstraint(graph.linkmodel,con)
    link_edge = add_edge!(graph,ref)  #adds edge and a contraint reference to all objects involved in the constraint
    return link_edge
end

#NOTE Figure out a good way to use containers here instead of making arrays
function addlinkconstraint{T}(graph::ModelGraph,linkcons::Array{AbstractConstraint,T})
    array_type = typeof(linkcons)  #get the array type
    array_type.parameters.length > 1? linkcons = vec(linkcons): nothing   #flatten out the constraints into a single vector

    #Check all of the constraints before I add one to the graph
    for con in linkcons
        vars = con.terms.vars
        nodes = unique([getnode(var) for var in vars])
        all(node->node in getnodes(graph),nodes)? nothing: error("the linkconstraint: $con contains variables that don't belong to the graph: $graph")
    end

    #Now add the constraints
    for con in linkcons
        addlinkconstraint(graph,con)
    end
end

#TODO
# function copy(graph::AbstractModelGraph)
#     nodes = getnodes(graph)
#     edges = getedges(graph)
#     copy_graph(graph)
#     Fill in other data
# end
getnodevariable(node::ModelNode,index::Integer) = Variable(getmodel(node),index)
function getnodevariablemap(node::ModelNode)
    node_map = Dict()
    node_model = getmodel(node)
    for key in keys(node_model.objDict)  #this contains both variable and constraint references
        if isa(node_model.objDict[key],Union{JuMP.JuMPArray{AbstractJuMPScalar},Array{AbstractJuMPScalar}})     #if the JuMP variable is an array or a JuMPArray
            vars = node_model.objDict[key]
            node_map[key] = vars
        #reproduce the same mapping in a dictionary
        elseif isa(node_model.objDict[key],JuMP.JuMPDict)
            tdict = node_model.objDict[key].tupledict  #get the tupledict
            d_tmp = Dict()
            for dkey in keys(tdict)
                d_tmp[dkey] = var_map[linearindex(tdict[dkey])]
            end
            node_map[key] = d_tmp

        elseif isa(node_model.objDict[key],JuMP.AbstractJuMPScalar) #else it's a single variable
            node_map[key] = node_model.objDict[key]
        # else #objDict also has contraints!
        #     error("Did not recognize the type of a JuMP variable $(node_model.objDict[key])")
        end
    end
    return node_map
end

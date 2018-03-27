import PlasmoGraphBase:add_node!,create_node
import Base:show,print,string,getindex,copy
import JuMP:AbstractModel,setobjective,getobjectivevalue
import LightGraphs.Graph
#import MathProgBase.SolverInterface:AbstractMathProgSolver

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

ModelGraph() = ModelGraph(BasePlasmoGraph(Graph),LinkModel(),Nullable())

setobjective(graph::ModelGraph, sense::Symbol, x::JuMP.Variable) = setobjective(graph.linkmodel, sense, convert(AffExpr,x))

getlinkconstraints(model::ModelGraph) = model.linkmodel.linkconstraints
gethyperconstraints(model::ModelGraph) = model.linkmodel.hyperconstraints

_setobjectivevalue(graph::ModelGraph,value::Number) = graph.linkmodel.objVal = value
JuMP.getobjectivevalue(graph::ModelGraph) = graph.linkmodel.objVal

getinternaljumpmodel(graph::ModelGraph) = graph.serial_model

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

#TODO Figure out how JuMP sets solvers now
#setsolver(model::PlasmoGraph,solver::AbstractMathProgSolver) = graph.solver = solver

##############################################################################
# Nodes
##############################################################################
mutable struct ModelNode <: AbstractModelNode
    basenode::BasePlasmoNode
    model::Nullable{AbstractModel}
    linkconref::Union{Void,ConstraintRef}
end

#Node constructors
#empty PlasmoNode
ModelNode() = ModelNode(BasePlasmoNode(),JuMP.Model(),nothing)
create_node(graph::ModelGraph) = ModelNode()

getmodel(node::ModelNode) = get(node.model)
hasmodel(node::ModelNode) = get(node.model) != nothing? true: false

getlinkconstraints(node::ModelNode) = node.link_data.linkconstraintmap
getlinkconstraints(graph::ModelGraph,node::ModelNode) = nodeoredge.link_data.linkconstraintmap[graph]

is_nodevar(node::ModelNode,var::AbstractJuMPScalar) = getmodel(node) == var.m #checks whether a variable belongs to a node or edge
_is_assignedtonode(m::AbstractModel) = haskey(m.ext,:node) #check whether a model is assigned to a node

getnode(m::AbstractModel) = _is_assignedtonode(m)? m.ext[:node] : throw(error("Only node models have associated graph nodes"))
getnode(var::AbstractJuMPScalar) = var.m.ext[:node]

#get variable index on a node
getindex(node::ModelNode,sym::Symbol) = getmodel(node)[sym]

function setmodel(node::ModelNode,m::AbstractModel)
    #_updatelinks(m,nodeoredge)      #update link constraints after setting a model
    !(_is_assignedtonode(m) && getmodel(node) == m) || error("the model is already asigned to another node")
    #If it already had a model, delete all the link constraints corresponding to that model
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

#TODO
#set a model with the same variable names and dimensions as the old model on the node.
#This will not break link constraints
function resetmodel(node::ModelNode,m::AbstractModel)
    #reassign the model
    node.model = m

    #switch out variables in any connected linkconstraints
    #throw warnings if link constraints break
end

#TODO
# removemodel(nodeoredge::NodeOrEdge) = nodeoredge.attributes[:model] = nothing  #need to update link constraints
##############################################################################
# Edges
##############################################################################
struct LinkingEdge <: AbstractLinkingEdge
    edge::BasePlasmoEdge
    linkconref::Union{Void,ConstraintRef}
end
#Edge constructors
LinkingEdge() = LinkingEdge(BasePlasmoEdge(),nothing)
create_edge(graph::ModelGraph) = LinkingEdge()

function add_edge!(graph::ModelGraph,ref::ConstraintReference)
    con = LinearConstraint(ref)
    nodes =
end

# TODO  Think of a good way to update links when swapping out models.  Might need to store variable names in NodeLinkData
# function _updatelinks(m,::AbstractModel,nodeoredge::NodeOrEdge)
#     link_cons = getlinkconstraints(nodeoredge)
#     #find variables
# end

#########################################
########################################
#Other add_node! constructors
#######################################
#Add nodes and set the model as well
function add_node!(graph::ModelGraph,m::AbstractModel)
    node = add_node!(graph)
    setmodel!(node,m)
    return node
end

#Store link constraint in the given graph.  Store a reference to the linking constraint on the nodes which it links
#TODO Create the edges on the graph between the nodes referenced in the link constraint
function addlinkconstraint(graph::ModelGraph,con::AbstractConstraint)
    # vars = con.terms.vars
    # #check that all of the variables belong to the same graph
    # nodes = unique([getnode(var) for var in vars])
    # all(node->node in getnodes(graph),nodes)? nothing: error("the linkconstraint: $con contains variables that don't belong to the graph: $graph")
    # if length(nodes) > 2
    #     push!(graph.linkmodel.hyperconstraints,con)
    # else
    #     push!(graph.linkmodel.linkconstraints,con)   #add the link constraint to the graph
    # end

    #ref = ConstraintRef{LinkModel,LinkConstraint}(graph.linkmodel, length(graph.linkmodel.linkconstraints) + length(graph.linkmodel.hyperconstraints))
    isa(con,LinearConstraint) || throw(error("Link constraints must be linear.  If you're trying to add quadtratic or nonlinear links, try creating duplicate variables and linking those"))
    ref = addconstraint(graph.linkmodel,con)
    link_edge = add_edge!(graph,ref)  #add a linking edge between the node variables

    #Update local node information
    for node in nodes
        add_link_reference(graph,node,ref)
    end
    return link_edge
end

#TODO Figure out a good way to use containers here instead of making arrays
function addlinkconstraint{T}(graph::ModelGraph,linkcons::Array{AbstractConstraint,T})
    array_type = typeof(linkcons)  #get the array type
    array_type.parameters.length > 1? linkcons = vec(linkcons): nothing   #flatten out the constraints into a single vector

    #Check all of the constraints before I add one to the graph
    for con in linkcons
        vars = con.terms.vars
        nodes = unique([getnode(var) for var in vars])
        all(node->node in values(getnodesandedges(graph)),nodes)? nothing: error("the linkconstraint: $con contains variables that don't belong to the graph: $graph")
    end

    #Now add the constraints
    for con in linkcons
        addlinkconstraint(graph,con)
    end
end

# function addconstraint(m::Model, c::AbstractConstraint, name::String="")
#     cindex = MOI.addconstraint!(m.moibackend, moi_function_and_set(c)...)
#     cref = ConstraintRef(m, cindex)
#     if !isempty(name)
#         setname(cref, name)
#     end
#     return cref
# end

# function setobjective(m::Model, sense::Symbol, a::AffExpr)
#     if length(graph.obj.qvars1) != 0
#         # Go through the quadratic path so that we properly clear
#         # current quadratic terms.
#         setobjective(graph, sense, convert(QuadExpr,a))
#     else
#         setobjectivesense(m, sense)
#         m.obj = convert(QuadExpr,a)
#     end
# end

#Add edges and set the model as well
# function add_edge!(graph::PlasmoGraph,edge::LightGraphs.Edge,m::AbstractModel)
#     pedge = add_edge!(graph,edge)
#     setmodel!(pedge,m)
#     return pedge
# end

# function add_edge!(graph::PlasmoGraph,pedge::PlasmoEdge,src::PlasmoNode,dst::PlasmoNode,m::AbstractModel)
#     pedge = add_edge!(graph,pedge,src,dst)
#     setmodel!(pedge,m)
#     return pedge
# end

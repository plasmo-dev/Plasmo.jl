##############################################################################
# Model Nodes
##############################################################################
mutable struct ModelNode <: AbstractModelNode
    basenode::BasePlasmoNode
    model::Nullable{AbstractModel}
    linkconrefs::Dict{ModelGraph,Vector{ConstraintRef}}
end

#Constructor
ModelNode() = ModelNode(BasePlasmoNode(),JuMP.Model(),Dict{ModelGraph,Vector{ConstraintRef}}())
create_node(graph::ModelGraph) = ModelNode()

function add_node!(graph::ModelGraph,m::AbstractModel)
    node = add_node!(graph)
    setmodel!(node,m)
    return node
end

getmodel(node::ModelNode) = get(node.model)
hasmodel(node::ModelNode) = get(node.model) != nothing? true: false
getindex(node::ModelNode,sym::Symbol) = getmodel(node)[sym]         #get variable index on a node

#Node objective value
JuMP.getobjective(node::ModelNode) = getobjective(node.model)
JuMP.getobjectivevalue(node::ModelNode) = getobjectivevalue(node.model)
setobjectivevalue(node::ModelNode,num::Number) = getmodel(node).objVal = num

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

#Get link constraints for a model node in graph
function getlinkconstraints(graph::ModelGraph,node::ModelNode)
    links = []
    for ref in node.linkconrefs[graph]
        push!(links,LinkConstraint(ref))
    end
    return links
end

########################################
# Get model node from other objects
########################################
is_nodevar(node::ModelNode,var::AbstractJuMPScalar) = getmodel(node) == var.m   #checks whether a variable belongs to a node or edge
_is_assignedtonode(m::AbstractModel) = haskey(m.ext,:node)                      #checks whether a model is assigned to a node
num_var(node::ModelNode) = MathProgBase.numvar(getmodel(node))

########################################
#Get model nodes corresponding to models or variables
########################################
getnode(m::AbstractModel) = _is_assignedtonode(m)? m.ext[:node] : throw(error("Only node models have associated graph nodes"))
getnode(var::AbstractJuMPScalar) = var.m.ext[:node]

function setmodel(node::ModelNode,m::AbstractModel;preserve_links = false)
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

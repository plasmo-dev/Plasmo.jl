##############################################################################
# Model Nodes
##############################################################################

#Constructor
"""
The ModelNode type

ModelNode()

Creates an empty ModelNode.  Does not add it to a graph.
"""
mutable struct ModelNode <: AbstractModelNode
    basenode::BasePlasmoNode
    model::Union{AbstractModel,Nothing}
    linkconrefs::Dict{AbstractModelGraph,Vector{ConstraintRef}}
end

#Constructor
ModelNode() = ModelNode(BasePlasmoNode(),JuMP.Model(),Dict{AbstractModelGraph,Vector{ConstraintRef}}())
create_node(graph::ModelGraph) = ModelNode()

"""
add_node!(graph::AbstractModelGraph)

Add a ModelNode to a ModelGraph.
"""
function add_node!(graph::AbstractModelGraph,m::AbstractModel)
    node = add_node!(graph)
    setmodel(node,m)
    return node
end

#Model Management
"Get the underlying JuMP model for a node"
getmodel(node::ModelNode) = node.model

"Check whethere a node has a model"
hasmodel(node::ModelNode) = node.model != nothing ? true : false

"Get an underlying model variable"
getindex(node::ModelNode,sym::Symbol) = getmodel(node)[sym]         #get variable index on a node

"""
getobjective(node::ModelNode)

Get a node objective.
"""
JuMP.getobjective(node::ModelNode) = getobjective(node.model)

"Get node objective value"
JuMP.getobjectivevalue(node::ModelNode) = getobjectivevalue(node.model)
setobjectivevalue(node::ModelNode,num::Number) = getmodel(node).objVal = num

"Retrieve all of the LinkConstraint references for a given node"
getlinkreferences(node::ModelNode) = node.linkconrefs

getlinkreferences(graph::AbstractModelGraph,node::ModelNode) = node.linkconrefs[graph]

"""
getlinkconstraints(node::ModelNode)

Return a Dictionary of LinkConstraints for each graph the node is a member of
"""
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

"""
getlinkconstraints(graph::AbstractModelGraph,node::ModelNode)

Return Array of LinkConstraints for the node
"""
function getlinkconstraints(graph::AbstractModelGraph,node::ModelNode)
    links = []
    for ref in node.linkconrefs[graph]
        push!(links,LinkConstraint(ref))
    end
    return links
end

########################################
# Get model node from other objects
########################################
"""
is_nodevar(node::ModelNode,var::AbstractJuMPScalar)

Check whether a JuMP variable belongs to a ModelNode
"""
is_nodevar(node::ModelNode,var::AbstractJuMPScalar) = getmodel(node) == var.m   #checks whether a variable belongs to a node or edge
_is_assignedtonode(m::AbstractModel) = haskey(m.ext,:node)                      #checks whether a model is assigned to a node
num_var(node::ModelNode) = MathProgBase.numvar(getmodel(node))

########################################
#Get model nodes corresponding to models or variables
########################################
"""
getnode(model::AbstractModel)

Get the ModelNode corresponding to a JuMP Model
"""
getnode(m::AbstractModel) = _is_assignedtonode(m) ? m.ext[:node] : throw(error("Only node models have associated graph nodes"))

"""
getnode(model::AbstractModel)

Get the ModelNode corresponding to a JuMP Variable
"""
getnode(var::AbstractJuMPScalar) = var.m.ext[:node]

"""
setmodel(node::ModelNode,m::AbstractModel)

Set the model on a node.  This will delete any link-constraints the node is currently part of
"""
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
# removemodel(node::ModelNode) = nodeoredge.attributes[:model] = nothing  #need to update link constraints

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

function string(node::ModelNode)
    "Model Node: "*"\n"*string("Member of $(length(getindices(node))) graph(s)")*"\n$(length(getmodel(node).colVal)) Variables"
end
print(io::IO,node::ModelNode) = print(io, string(node))
show(io::IO,node::ModelNode) = print(io,node)

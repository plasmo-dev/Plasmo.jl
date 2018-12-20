#Node map which allows back and forth node lookup
mutable struct NodeDict
    id_dict::Dict{Int,AbstractPlasmoNode}    #Integer -> Node
    node_dict::Dict{AbstractPlasmoNode,Int}  #Node -> Integer
end
NodeDict() = NodeDict(Dict{Int, AbstractPlasmoNode}(), Dict{AbstractPlasmoNode,Int}())

#Edge map which allows back forth edge lookup
mutable struct EdgeDict
    id_dict::Dict{AbstractEdge,AbstractPlasmoEdge}
    edge_dict::Dict{AbstractPlasmoEdge,AbstractEdge}
end
EdgeDict() = EdgeDict(Dict{AbstractEdge, AbstractPlasmoEdge}(), Dict{AbstractPlasmoEdge,AbstractEdge}())


"""
    nodes(ns::NodeDict) ->

Return an iterable of all nodes stored in the `NodeDict`
"""
nodes(nd::NodeDict) = keys(nd.node_dict)
edges(ed::EdgeDict) = keys(ed.edge_dict)

"""
    length(nd::NodeDict) -> Integer

Return the number of nodes in a node set.
"""
Base.length(nd::NodeDict) = length(nd.id_dict)
Base.length(ed::EdgeDict) = length(ed.id_dict)

"""
    in(node::AbstractPlasmoNode, nd::NodeDict) -> Bool

Determine whether a node is in a node dict.
"""
Base.in(node::AbstractPlasmoNode, nd::NodeDict) = node in keys(nd.node_dict)
Base.in(edge::AbstractPlasmoEdge, ed::EdgeDict) = edge in keys(ed.edge_dict)

#NOTE: Gone in Julia 1.0
# """
#     findin(nd::NodeDict, nodes) -> Vector{Int}
#
# Return the node numbers of all nodes in the node dict which are present in the `nodes`
# iterable of AbstractPlasmoNodes.
# """
# function Base.findin(nd::NodeDict, nodes)
#     numbers = Int[]
#     for node in nodes
#         number = get(nd.node_dict, node, 0)
#         if number != 0
#             push!(numbers, number)
#         end
#     end
#     return numbers
# end

"""
    getindex(nd::NodeDict, node_id::Int) -> AbstractPlasmoNode

Return the AbstractPlasmoNode from a node dict corresponding to a given integer id.
"""
Base.getindex(nd::NodeDict, node_id::Int) = nd.id_dict[node_id]
Base.getindex(ed::EdgeDict, edge_pair::AbstractEdge) = ed.id_dict[edge_pair]

"""
    getindex(ns::NodeDict, node::AbstractPlasmoNode) -> Int

Return the integer id from a node dict corresponding to a given `AbstractPlasmoNode`
"""
Base.getindex(nd::NodeDict, node::AbstractPlasmoNode) = nd.node_dict[node]
Base.getindex(ed::EdgeDict, edge::AbstractPlasmoEdge) = ed.edge_dict[edge]

#Just going to avoid push here
"""
    add_node!(nd::NodeDict, node::AbstractPlasmoNode) -> NodeDict

Add a node to a node dict. Return the first argument.
"""
function add_node!(nd::NodeDict, node::AbstractPlasmoNode)
    if !(node in nd)
        new_index = length(nd) + 1
        nd[new_index] = node        #calls setindex to get reverse mapping
    end
    return nd
end

function add_node!(nd::NodeDict, node::AbstractPlasmoNode,index::Int)
    if !(node in nd)
        new_index = index
        nd[new_index] = node        #calls setindex to get reverse mapping
    end
    return nd
end

#add a plasmo edge which is indexed by a simple LightGraphs AbstractEdge
function add_edge!(ed::EdgeDict, plasmoedge::AbstractPlasmoEdge, edge::AbstractEdge)
    if !(plasmoedge in ed)
        ed[edge] = plasmoedge       #calls setindex to get reverse mapping
    end
    return ed
end

"""
    setindex!(nd::NodeDict, node::AbstractPlasmoNode, node_id::Int) -> NodeDict

Replace the node corresponding to a given integer id with a given AbstractPlasmoNode.
Return the NodeDict.
"""
function Base.setindex!(nd::NodeDict, node::AbstractPlasmoNode, node_id::Int)
    #delete the old node from the dict if this index is already taken
    if node_id in keys(nd.id_dict)
        old_node = nd.id_dict[node_id]
        delete!(nd.node_dict, old_node)
    end

    #set both mappings
    nd.node_dict[node] = node_id
    nd.id_dict[node_id] = node
    return nd
end

function Base.setindex!(ed::EdgeDict, edge::AbstractPlasmoEdge, edge_id::AbstractEdge)
    if edge_id in keys(ed.id_dict)
        #delete the old node from the dict
        old_edge = ed.id_dict[edge_id]
        delete!(ed.edge_dict, old_edge)
    end

    #set both mappings
    ed.edge_dict[edge] = edge_id
    ed.id_dict[edge_id] = edge
    return ed
end

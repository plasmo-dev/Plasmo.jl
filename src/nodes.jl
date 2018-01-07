#Node map which allows back and forth node lookup
mutable struct NodeDict
    id_dict::Dict{Int,AbstractNode}
    node_dict::Dict{AbstractNode,Int}
end
NodeDict() = NodeDict(Dict{Int, AbstractNode}(), Dict{AbstractNode,Int}())

#Edge map which allows back forth edge lookup
mutable struct EdgeDict
    id_dict::Dict{Pair,AbstractEdge}
    edge_dict::Dict{AbstractEdge,Pair}
end
EdgeDict() = EdgeDict(Dict{Pair, AbstractEdge}(), Dict{AbstractEdge,Pair}())

"""
    length(nd::NodeDict) -> Integer

Return the number of nodes in a node set.
"""
Base.length(nd::NodeDict) = length(nd.id_dict)


"""
    in(node::AbstractPlasmoNode, nd::NodeDict) -> Bool

Determine whether a node is in a node dict.
"""
Base.in(node::AbstractPlasmoNode, nd::NodeDict) = node in keys(nd.node_dict)

"""
    push!(nd::NodeDict, node::AbstractPlasmoNode) -> NodeDict

Add a node to a node set. Return the first argument.
"""
function Base.push!(nd::NodeDict, node::AbstractPlasmoNode)
    if !(node in nd)
        new_index = length(nd) + 1
        nd[new_index] = node  #should use setindex to get reverse mapping
    end
    return nd
end

"""
    findin(nd::NodeDict, nodes) -> Vector{Int}

Return the node numbers of all nodes in the node dict which are present in the `nodes`
iterable of AbstractPlasmoNodes.
"""
function Base.findin(nd::NodeDict, nodes)
    numbers = Int[]
    for node in nodes
        number = get(nd.node_dict, node, 0)
        if number != 0
            push!(numbers, number)
        end
    end
    return numbers
end

"""
    nodes(ns::NodeDict) ->

Return an iterable of all nodes stored in the `NodeDict`
"""
nodes(nd::NodeDict) = keys(nd.node_dict)

"""
    getindex(nd::NodeDict, node_id::Int) -> AbstractPlasmoNode

Return the AbstractPlasmoNode from a node dict corresponding to a given integer id.
"""
Base.getindex(nd::NodeDict, node_id::Int) = nd.id_dict[node_id]

"""
    getindex(ns::NodeDict, node::AbstractPlasmoNode) -> Int

Return the integer id from a node dict corresponding to a given `AbstractPlasmoNode`
"""
Base.getindex(nd::NodeSet, node::AbstractPlasmoNode) = nd.node_dict[node]

# there is no setindex!(::NodeDict, ::Int, ::AbstractPlasmoNode) because of the way
# LightGraphs stores graphs as contiguous ranges of integers.

"""
    setindex!(nd::NodeDict, node::AbstractPlasmoNode, node_id::Int) -> NodeDict

Replace the node corresponding to a given integer id with a given AbstractPlasmoNode.
Return the NodeDict.
"""
function Base.setindex!(nd::NodeDict, node::AbstractPlasmoNode, node_id::Int)
    if node_id in keys(nd.id_dict)
        #delete the old node from the dict
        old_node = nd.id_dict[node_id]
        delete!(nd.node_dict, old_node)
    end

    #set both mappings
    nd.node_dict[node] = node_id
    nd.id_dict[node_id] = node
    return nd
end

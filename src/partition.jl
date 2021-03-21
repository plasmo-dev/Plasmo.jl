# The Partition object describes partitions of optinodes and optiedges.
# Different graph projections can be used to create a Partition object which is the standard interface to form subgraphs
abstract type AbstractPartition end
"""
    Partition(hypergraph::HyperGraph,node_membership_vector::Vector{Int64},ref_map::Dict)

Create a partition of optinodes using `hypergraph`, `node_membership_vector`, and 'ref_map'.  The 'ref_map' is a dictionary that maps hypernode indices (integers) and hyperedge indices (tuples) back to optinodes and optiedges.

    Partition(optigraph::OptiGraph,node_membership_vector::Vector{Int64},ref_map::Dict)

Create a partition using `optigraph`, `node_membership_vector`, and 'ref_map'. The `ref_map` is a mapping of node_indices to the original optinodes.

    Partition(optigraph::OptiGraph,optinode_vectors::Vector{Vector{OptiNode}})

Manually create a partition using `optigraph` and a vector of vectors containing sets of optinodes that represent each partition.
"""
mutable struct Partition <: AbstractPartition
    optinodes::Vector{OptiNode}   #optinodes at partition level
    optiedges::Vector{OptiEdge}   #optiedges at partition level
    subpartitions::Vector{AbstractPartition}      #subpartitions
end
Partition() = Partition(Vector{OptiNode}(),Vector{OptiEdge}(),Vector{Partition}())

#TODO: Check partition structure
function _check_valid_partition()
    #No duplicate nodes in partition
    #Edges cover the nodes
end

#NODE PARTITION
#Partition with a HyperGraph and a reference map
function Partition(hypergraph::HyperGraph,node_membership_vector::Vector{Int64},ref_map::Dict)
    partition = Partition()
    hypernode_vectors = partition_list(hypergraph,node_membership_vector)
    induced_edge_partitions,cross_edges = identify_edges(hypergraph,hypernode_vectors)
    @assert length(hypernode_vectors) == length(induced_edge_partitions)

    partition.optiedges = getindex.(Ref(ref_map),cross_edges)
    for i = 1:length(hypernode_vectors)
        subpartition = Partition()
        subpartition.optinodes = getindex.(Ref(ref_map),hypernode_vectors[i])
        subpartition.optiedges = getindex.(Ref(ref_map),induced_edge_partitions[i])
        push!(partition.subpartitions,subpartition)
    end
    return partition
end

#Partition with vectors of optinodes
function Partition(graph::OptiGraph,optinode_vectors::Vector{Vector{OptiNode}})
    partition = Partition()
    optiedge_vectors,cross_edges = identify_edges(graph,optinode_vectors)
    @assert length(optinode_vectors) == length(optiedge_vectors)
    partition.optiedges = cross_edges
    for i = 1:length(optinode_vectors)
        subpartition = Partition()
        subpartition.optinodes = optinode_vectors[i]
        subpartition.optiedges = optiedge_vectors[i]
        push!(partition.subpartitions,subpartition)
    end
    return partition
end

#Use an OptiGraph and a reference map
function Partition(graph::OptiGraph,node_membership_vector::Vector{Int64},ref_map::Dict)
    optinode_vectors = partition_list(graph,node_membership_vector,ref_map)
    return Partition(graph,optinode_vectors)
end

#Use graph_backend to make Partition
function Partition(graph::OptiGraph,node_membership_vector::Vector{Int64})
    hypergraph,ref_map = graph_backend(graph)
    optinode_vectors = partition_list(graph,node_membership_vector,ref_map)
    return Partition(graph,optinode_vectors)
end

#EDGE PARTITION
#Partition with vectors of optiedges
function Partition(graph::OptiGraph,optiedge_vectors::Vector{Vector{OptiEdge}})
    partition = Partition()
    optinode_vectors,cross_nodes = identify_nodes(graph,optiedge_vectors)
    @assert length(optinode_vectors) == length(optiedge_vectors)
    node_incident_edges = Plasmo.incident_edges(graph,cross_nodes) #incident edges to root partition nodes are also in root
    partition.optinodes = cross_nodes
    partition.optiedges = node_incident_edges
    for i = 1:length(optiedge_vectors)
        subpartition = Partition()
        subpartition.optinodes = optinode_vectors[i]
        subpartition.optiedges = setdiff(optiedge_vectors[i],node_incident_edges) #cut out the root incident edges
        push!(partition.subpartitions,subpartition)
    end
    return partition
end

#NODE-EDGE PARTITION (e.g. partitioning a bipartite graph)
function Partition(graph::OptiGraph,subgraphs::Vector{OptiGraph})
end
#Partition with vectors of shared nodes and edges
# function Partition(graph::OptiGraph,cross_nodes::Vector{OptiNode},cross_edges::Vector{OptiEdge})
# end




getnodes(partition::Partition) = partition.optinodes
getedges(partition::Partition) = partition.optiedges
getsubpartitions(partition::Partition) = partition.subpartitions

function all_subpartitions(partition::Partition)
    subparts = partition.subpartitions
    for part in subparts
        subparts = [subparts;all_subpartitions(part)]
    end
    return subparts
end

function n_subpartitions(partition::Partition)
    n_subparts = length(partition.subpartitions)
    subparts = partition.subpartitions
    for part in subparts
        n_subparts += n_subpartitions(part)
    end
    return n_subparts
end

"""
    make_subgraphs!(optigraph::OptiGraph,partition::Partition)

Create subgraphs in `optigraph` using a produced 'partition'.
"""
function make_subgraphs!(graph::OptiGraph,partition::Partition)
    root = partition
    graph.subgraphs = OptiGraph[]

    optinodes = root.optinodes
    optiedges = root.optiedges

    _set_nodes(graph,optinodes)
    _set_edges(graph,optiedges)
    subparts = root.subpartitions
    #Create subgraph structure from nodes and partition data
    for subpartition in subparts
        subgraph = OptiGraph()
        add_subgraph!(graph,subgraph)
        make_subgraphs!(subgraph,subpartition)
    end
    return nothing
end

#Create a new set of nodes on a optigraph
function _set_nodes(graph::OptiGraph,nodes::Vector{OptiNode})
    graph.optinodes = nodes
    for (idx,node) in enumerate(graph.optinodes)
        graph.node_idx_map[node] = idx
    end
    return nothing
end

#Create a new set of edges on a optigraph
function _set_edges(graph::OptiGraph,edges::Vector{OptiEdge})
    graph.optiedges = edges
    link_idx = 0
    for (idx,optiedge) in enumerate(graph.optiedges)
        graph.edge_idx_map[optiedge] = idx
        graph.optiedge_map[optiedge.nodes] = optiedge
    end
    return nothing
end


####################################
#Print Functions
####################################
function string(partition::Partition)
    """
        OptiGraph Partition w/ $(n_subpartitions(partition)) subpartitions
    """
end
print(io::IO, partition::Partition) = print(io, string(partition))
show(io::IO,partition::Partition) = print(io,partition)

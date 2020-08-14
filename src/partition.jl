# The Partition object describes partitions of optinodes and optiedges.
# Different graph projections can be used to create an intermediate Partition object which is the standard interface to make subgraphs
abstract type AbstractPartition end
###########################################################################################################
#Note that a Partition can contain subpartitions recursively
"""
    Partition(hypergraph::HyperGraph,node_membership_vector::Vector{Int64},ref_map::Dict)

Create a partition of optinodes using `hypergraph`, `node_membership_vector`, and 'ref_map'.  The 'ref_map' is a dictionary that maps hypernode indices (integers) and hyperedge indices (tuples) back to optinodes and optiedges.

    Partition(optigraph::OptiGraph,node_membership_vector::Vector{Int64},ref_map::Dict)

Create a partition using `optigraph`, `node_membership_vector`, and 'ref_map'. The `ref_map` is a mapping of node_indices to the original optinodes.

    Partition(optigraph::OptiGraph,optinode_vectors::Vector{Vector{OptiNode}})

Manually create a partition using `optigraph` and a vector of vectors containing sets of optinodes that represent each partition.
"""
mutable struct Partition <: AbstractPartition
    optinodes::Vector{OptiNode}   #hypernodes at this level
    optiedges::Vector{OptiEdge}   #hyperedges at his level
    parent::Union{Nothing,AbstractPartition} #parent partition
    subpartitions::Vector{AbstractPartition}      #subpartitions
end
Partition() = Partition(Vector{OptiNode}(),Vector{OptiEdge}(),nothing,Vector{Partition}())

function Partition(hypergraph::HyperGraph,node_membership_vector::Vector{Int64},ref_map::Dict)
    partition = Partition()
    hypernode_vectors = getpartitionlist(hypergraph,node_membership_vector)
    induced_edge_partitions,cross_edges = identify_edges(hypergraph,hypernode_vectors)
    @assert length(hypernode_vectors) == length(induced_edge_partitions)

    partition.optiedges = getindex.(Ref(ref_map),cross_edges)
    for i = 1:length(hypernode_vectors)
        subpartition = Partition()
        subpartition.optinodes = getindex.(Ref(ref_map),hypernode_vectors[i])
        subpartition.optiedges = getindex.(Ref(ref_map),induced_edge_partitions[i])
        subpartition.parent = partition
        push!(partition.subpartitions,subpartition)
    end
    return partition
end

function Partition(graph::OptiGraph,node_membership_vector::Vector{Int64},ref_map::Dict)
    optinode_vectors = getpartitionlist(graph,node_membership_vector,ref_map)
    return Partition(graph,optinode_vectors)
end

function Partition(mg::OptiGraph,optinode_vectors::Vector{Vector{OptiNode}})
    partition = Partition()
    optiedge_vectors,cross_edges = identify_edges(mg,optinode_vectors)
    @assert length(optinode_vectors) == length(optiedge_vectors)
    partition.optiedges = cross_edges
    for i = 1:length(optinode_vectors)
        subpartition = Partition()
        subpartition.optinodes = optinode_vectors[i]
        subpartition.optiedges = optiedge_vectors[i]
        subpartition.parent = partition
        push!(partition.subpartitions,subpartition)
    end
    return partition
end

getnodes(partition::Partition) = partition.optinodes
getedges(partition::Partition) = partition.optiedges
getparent(partition::Partition) = partition.parent
getsubparts(partition::Partition) = partition.subpartitions

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

#Turn graph into subgraph-based structure
"""
    make_subgraphs!(optigraph::OptiGraph,partition::Partition)

Create subgraphs in `optigraph` using a produced 'partition'.
"""
function make_subgraphs!(graph::OptiGraph,partition::Partition)
    root = partition
    graph.subgraphs = OptiGraph[]

    mnodes = root.optinodes
    ledges = root.optiedges

    _set_nodes(graph,mnodes)
    _set_edges(graph,ledges)
    subparts = root.subpartitions
    #Create subgraph structure from nodes and partition data
    for subpartition in subparts
        subgraph = OptiGraph()
        add_subgraph!(graph,subgraph)
        make_subgraphs!(subgraph,subpartition)
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


#TODO
# function Partition(clique_graph::DualCliqueGraph,projection_map::ProjectionMap,membership_vector::Vector{Int64}) #NOTE: Could also be a Dual Clique Graph
#
#     hyperpartition = HyperPartition()
#
#     #figure out the hypergraph partition based on the graph partition
#
#     return hyperpartition
# end
#
# function Partition(bipartite_graph::BipartiteGraph,projection_map::ProjectionMap,membership_vector::Vector{Int64};selection = :shared_nodes)
#
#     hyperpartition = HyperPartition()
#
#     return hyperpartition
# end
#
# function Partition(dual_hyper_graph::AbstractHyperGraph,projection_map::ProjectionMap,membership_vector::Vector{Int64})
#
#     hyperpartition = HyperPartition()
#
#     return hyperpartition
# end
#
# #TODO: Check Partition makes sense
# function Partition(hypergraph::HyperGraph,node_membership_vector::Vector{Int64})
#     partition = Partition()
#
#     #convert membership vector to vector of vectors
#     hypernode_vectors = getpartitionlist(hypergraph,node_membership_vector)
#     induced_edge_partitions,shared_edges = identify_edges(hypergraph,hypernode_vectors)
#     @assert length(hypernode_vectors) == length(induced_edge_partitions)
#
#     partition.hyperedges = shared_edges
#     for i = 1:length(hypernode_vectors)
#         subpartition = Partition()
#         subpartition.hypernodes = hypernode_vectors[i]
#         subpartition.hyperedges = induced_edge_partitions[i]
#         subpartition.parent = partition
#         push!(partition.subpartitions,subpartition)
#     end
#     return partition
# end

#NOTE (s)
# end
# #Case 0
# hypergraph = gethypergraph(optigraph)  #OR getlinkvarhypergraph(optigraph)  #hypergraph with a node for the master problem.  the linknode gets index 0
# membership_vector = KaHyPar.partition(hypergraph)
# model_partition = ModelPartition(hypergraph,membership_vector)  #create hypergraph partitions, find shared hyperedges
#
# #Case 1
# hypergraph = gethypergraph(model_graph)  #option to add node for master
# clique_graph, projection_map = clique_expansion(hyper_graph)  #conversion map maps nodes and edges back to hypergraph
# membership_vector = Metis.partition(clique_graph)  #e.g. [1,2,1,1,3,2,2,2,3,4,4,4]
# hyper_partition = HyperPartition(clique_graph,projection_map,membership_vector)
# new_graph, agg_map = aggregate(optigraph,hyper_partition)
#
# #Case 2
# hypergraph = gethypergraph(model_graph)
# dual_graph, projection_map = dual_hyper_graph(hypergraph)
# membership_vector = KaHyPar.partition(dual_graph,4)
# model_partition = ModelPartition(dual_hyper_graph,projection_map,membership_vector)
#
# #Case 3
# hypergraph = gethypergraph(model_graph)
# bipartite_graph, projection_map = star_expansion(hypergraph)
# membership_vector = Metis.partition(bipartite_graph,4)
# model_partition = ModelPartition(bipartite_graph,projection_map,membership_vector;selection = :shared_nodes)
#
# #Case 4
# hypergraph = gethypergraph(model_graph)
# dual_clique_graph, projection_map = dual_clique_expansion(hypergraph)
# membership_vector = Metis.partition(dual_clique_graph,4)
# model_partition = ModelPartition(dual_clique_graph,projection_map,membership_vector)
# #get hypergraphs using induced subgraph

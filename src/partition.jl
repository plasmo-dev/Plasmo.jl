# The Partition object describes partitions of modelnodes and linkedges.
# Different graph projections can be used to create an intermediate Partition object which is the standard interface to make subgraphs
abstract type AbstractPartition end
###########################################################################################################
#Note that a Partition can contain subpartitions recursively
mutable struct Partition <: AbstractPartition
    modelnodes::Vector{ModelNode}   #hypernodes at this level
    linkedges::Vector{LinkEdge}   #hyperedges at his level
    parent::Union{Nothing,AbstractPartition} #parent partition
    subpartitions::Vector{AbstractPartition}      #subpartitions
end
Partition() = Partition(Vector{ModelNode}(),Vector{LinkEdge}(),nothing,Vector{Partition}())

function Partition(hypergraph::HyperGraph,node_membership_vector::Vector{Int64},ref_map::Dict)
    partition = Partition()
    hypernode_vectors = getpartitionlist(hypergraph,node_membership_vector)
    induced_edge_partitions,cross_edges = identify_edges(hypergraph,hypernode_vectors)
    @assert length(hypernode_vectors) == length(induced_edge_partitions)

    partition.linkedges = getindex.(Ref(ref_map),cross_edges)
    for i = 1:length(hypernode_vectors)
        subpartition = Partition()
        subpartition.modelnodes = getindex.(Ref(ref_map),hypernode_vectors[i])
        subpartition.linkedges = getindex.(Ref(ref_map),induced_edge_partitions[i])
        subpartition.parent = partition
        push!(partition.subpartitions,subpartition)
    end
    return partition
end

function Partition(mg::ModelGraph,modelnode_vectors::Vector{Vector{ModelNode}})
    partition = Partition()
    linkedge_vectors,cross_edges = identify_edges(mg,modelnode_vectors)
    @assert length(modelnode_vectors) == length(linkedge_vectors)
    partition.linkedges = cross_edges
    for i = 1:length(modelnode_vectors)
        subpartition = Partition()
        subpartition.modelnodes = modelnode_vectors[i]
        subpartition.linkedges = linkedge_vectors[i]
        subpartition.parent = partition
        push!(partition.subpartitions,subpartition)
    end
    return partition
end

getnodes(partition::Partition) = partition.modelnodes
getedges(partition::Partition) = partition.linkedges
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
function make_subgraphs!(graph::ModelGraph,partition::Partition)
    root = partition
    graph.subgraphs = ModelGraph[]

    mnodes = root.modelnodes
    ledges = root.linkedges

    _set_nodes(graph,mnodes)
    _set_edges(graph,ledges)
    subparts = root.subpartitions
    #Create subgraph structure from nodes and partition data
    for subpartition in subparts
        subgraph = ModelGraph()
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
    ModelGraph Partition w/ $(n_subpartitions(partition)) subpartitions
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
# hypergraph = gethypergraph(modelgraph)  #OR getlinkvarhypergraph(modelgraph)  #hypergraph with a node for the master problem.  the linknode gets index 0
# membership_vector = KaHyPar.partition(hypergraph)
# model_partition = ModelPartition(hypergraph,membership_vector)  #create hypergraph partitions, find shared hyperedges
#
# #Case 1
# hypergraph = gethypergraph(model_graph)  #option to add node for master
# clique_graph, projection_map = clique_expansion(hyper_graph)  #conversion map maps nodes and edges back to hypergraph
# membership_vector = Metis.partition(clique_graph)  #e.g. [1,2,1,1,3,2,2,2,3,4,4,4]
# hyper_partition = HyperPartition(clique_graph,projection_map,membership_vector)
# new_graph, agg_map = aggregate(modelgraph,hyper_partition)
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

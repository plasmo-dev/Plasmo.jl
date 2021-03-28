function KaHyPar.partition(graph::HyperGraph,n_parts::Int64;edge_weights = ones(length(graph.hyperedge_map)),node_sizes = ones(length(graph.vertices)),kwargs...)
    A = incidence_matrix(graph)

    node_sizes = Int64.(node_sizes)
    edge_weights = Int64.(edge_weights)

    kgraph = KaHyPar.hypergraph(A,node_sizes,edge_weights)
    partition_vector = KaHyPar.partition(kgraph,n_parts;kwargs...)
    return partition_vector
end

function KaHyPar.partition(graph::BipartiteGraph,n_parts::Int64;node_sizes = ones(LightGraphs.nv(graph)),edge_weights = ones(LightGraphs.ne(graph)),kwargs...)
    A = incidence_matrix(graph.graph)

    node_sizes = Int64.(node_sizes)
    edge_weights = Int64.(edge_weights)

    kgraph = KaHyPar.hypergraph(A,node_sizes,edge_weights)
    partition_vector = KaHyPar.partition(kgraph,n_parts;kwargs...)
    return partition_vector
end

# function KaHyPar.partition(graph::LightGraphs.AbstractGraph,n_parts::Int64;edge_weights = ones(length(graph.hyperedge_map)),node_sizes = ones(length(graph.vertices)),kwargs...)
#     A = incidence_matrix(graph)
#
#     node_sizes = Int64.(node_sizes)
#     edge_weights = Int64.(edge_weights)
#
#     kgraph = KaHyPar.hypergraph(A,node_sizes,edge_weights)
#     partition_vector = KaHyPar.partition(kgraph,n_parts;kwargs...)
#     return partition_vector
# end

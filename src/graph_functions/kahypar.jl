"""
	KaHyPar.partition(graph::OptiGraph, n_parts::Int64; kwargs...)

Partition an optigraph with KaHyPar by creating a hypergraph projection.
"""
function KaHyPar.partition(graph::OptiGraph, n_parts::Int64; kwargs...)
   	projection = hyper_projection(graph)
    A = GOI.incidence_matrix(projection.projected_graph)
    node_sizes = [num_variables(node) for node in all_nodes(graph)]
    edge_weights = [num_constraints(node) for node in all_nodes(graph)]
    kgraph = KaHyPar.HyperGraph(A, node_sizes, edge_weights)
    partition_vector = KaHyPar.partition(kgraph, n_parts; kwargs...)
    return partition_vector
end

"""
	KaHyPar.partition(
	    graph::HyperGraph,
	    n_parts::Int64;
	    edge_weights=ones(length(graph.hyperedge_map)),
	    node_sizes=ones(length(graph.vertices)),
	    kwargs...,
	)

Partition a Projection using KaHyPar.
"""
function KaHyPar.partition(
    projection::GraphProjection,
    n_parts::Int64;
    edge_weights=ones(Graphs.ne(projection.projected_graph)),
    node_sizes=ones(Graphs.nv(projection.projected_graph)),
    kwargs...,
)
    A = GOI.incidence_matrix(projection.projected_graph)
    node_sizes = Int64.(node_sizes)
    edge_weights = Int64.(edge_weights)
    kgraph = KaHyPar.HyperGraph(A, node_sizes, edge_weights)
    partition_vector = KaHyPar.partition(kgraph, n_parts; kwargs...)
    return partition_vector
end
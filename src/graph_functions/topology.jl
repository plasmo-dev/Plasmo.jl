const HyperGraphProjection = GraphProjection{GOI.HyperGraph,HyperGraphProjectionType}

"""
    Graphs.all_neighbors(hyper::HyperGraphProjection, node::OptiNode)

Retrieve the optinode neighbors of `node` in the optigraph `graph`.  
Uses an underlying hypergraph to query for neighbors.
"""
function Graphs.all_neighbors(hyper::HyperGraphProjection, node::OptiNode)
    vertex = hyper[node]
    neighbors = Graphs.all_neighbors(hyper.projected_graph, vertex)
    return get_mapped_elements(hyper, neighbors)
end

"""
    Graphs.induced_subgraph(graph::OptiGraph, nodes::Vector{OptiNode})

Create an induced subgraph of optigraph given a vector of optinodes.
"""
function Graphs.induced_subgraph(
    hyper::HyperGraphProjection, nodes::Vector{<:OptiNode}; name=nothing
)
    edges = induced_edges(hyper, nodes)
    induced_graph = assemble_optigraph(nodes, edges; name=name)
    return induced_graph
end

"""
    incident_edges(hyper::HyperGraphProjection, nodes::Vector{OptiNode})

Retrieve incident edges to a set of optinodes.

    incident_edges(hyper::HyperGraphProjection, node::OptiNode)

Retrieve incident edges to a single optinode.
"""
function incident_edges(hyper::HyperGraphProjection, nodes::Vector{<:OptiNode})
    hypernodes = Base.getindex.(Ref(hyper), nodes)
    #hypernodes = get_mapped_elements(hyper, nodes)
    inc_edges = GOI.incident_edges(hyper.projected_graph, hypernodes)
    return get_mapped_elements(hyper, inc_edges)
end

function incident_edges(hyper::HyperGraphProjection, node::OptiNode)
    return incident_edges(hyper, [node])
end

"""
    induced_edges(graph::OptiGraph, nodes::Vector{OptiNode})

Retrieve induced edges to a set of optinodes.
"""
function induced_edges(hyper::HyperGraphProjection, nodes::Vector{<:OptiNode})
    hypernodes = get_mapped_elements(hyper, nodes)
    induced = GOI.induced_edges(hyper.projected_graph, hypernodes)
    optiedges = convert(Vector{OptiEdge}, get_mapped_elements(hyper, induced))
    return optiedges
end

"""
    identify_edges(hyper::HyperGraphProjection, node_vectors::Vector{Vector{OptiNode}})

Identify induced edges and edge separators from a vector of optinode partitions.

# Arguments
- `hyper::HyperGraphProjection`: A `HyperGraphProjection` obtained from `hyper_projection`.
- `node_vectors::Vector{Vector{OptiNode}}`: A vector of vectors that contain `OptiNode`s.

# Returns
- partition_optiedges::Vector{Vector{OptiEdge}}: The `OptiEdge` vectors for each partition.
- cross_optiedges::Vector{OptiEdge}: A vector of optiedges that cross partitions.
"""
function identify_edges(
    hyper::HyperGraphProjection, node_vectors::Vector{<:Vector{<:OptiNode}}
)
    hypernode_vectors = get_mapped_elements.(Ref(hyper), node_vectors)
    partition_edges, cross_edges = GOI.identify_edges(
        hyper.projected_graph, hypernode_vectors
    )
    partition_optiedges = get_mapped_elements.(Ref(hyper), partition_edges)
    cross_optiedges = get_mapped_elements(hyper, cross_edges)
    return partition_optiedges, cross_optiedges
end

"""
    identify_nodes(hyper::HyperGraphProjection, node_vectors::Vector{Vector{OptiEdge}})

Identify induced nodes and node separators from a vector of optiedge partitions.
"""
function identify_nodes(
    hyper::HyperGraphProjection, edge_vectors::Vector{<:Vector{<:OptiEdge}}
)
    hyperedge_vectors = get_mapped_elements.(Ref(hyper), edge_vectors)
    partition_nodes, cross_nodes = GOI.identify_nodes(
        hyper.projected_graph, hyperedge_vectors
    )
    partition_optinodes = get_mapped_elements.(Ref(hyper), partition_nodes)
    cross_optinodes = get_mapped_elements(hyper, cross_nodes)
    return partition_optinodes, cross_optinodes
end

"""
    neighborhood(
        hyper::HyperGraphProjection, 
        nodes::Vector{OptiNode}, 
        distance::Int64
    )::Vector{OptiNode}

Return the optinodes within `distance` of the given `nodes` in the optigraph `graph`.
"""
function Graphs.neighborhood(
    hyper::HyperGraphProjection, nodes::Vector{<:OptiNode}, distance::Int64
)
    vertices = get_mapped_elements(hyper, nodes)
    new_nodes = GOI.neighborhood(hyper.projected_graph, vertices, distance)
    return get_mapped_elements(hyper, new_nodes)
end

"""
    expand(hyper::HyperGraphProjection, subgraph::OptiGraph, distance::Int64)

Return a new expanded subgraph given the optigraph `graph` and an existing subgraph `subgraph`.
The returned subgraph contains the expanded neighborhood within `distance` of the given `subgraph`.
"""
function expand(
    hyper::HyperGraphProjection, subgraph::OptiGraph, distance::Int64; name=nothing
)
    nodes = all_nodes(subgraph)
    return expand(hyper, nodes, distance; name=name)
end

function expand(
    hyper::HyperGraphProjection, nodes::Vector{<:OptiNode}, distance::Int64; name=nothing
)
    new_optinodes = Graphs.neighborhood(hyper, nodes, distance)
    new_optiedges = induced_edges(hyper, new_optinodes)
    expanded_subgraph = assemble_optigraph(new_optinodes, new_optiedges; name=name)
    return expanded_subgraph
end

const HyperMap = ProjectionMap{GOI.HyperGraph,HyperGraphProjection}

"""
    Graphs.all_neighbors(hyper_map::HyperMap, node::OptiNode)

Retrieve the optinode neighbors of `node` in the optigraph `graph`.  
Uses an underlying hypergraph to query for neighbors.
"""
function Graphs.all_neighbors(hyper_map::HyperMap, node::OptiNode)
    vertex = hyper_map[node]
    neighbors = Graphs.all_neighbors(hyper_map.projected_graph, vertex)
    return get_mapped_elements(hyper_map, neighbors)
end

"""
    Graphs.induced_subgraph(graph::OptiGraph, nodes::Vector{OptiNode})

Create an induced subgraph of optigraph given a vector of optinodes.
"""
function Graphs.induced_subgraph(hyper_map::HyperMap, nodes::Vector{OptiNode})
    edges = induced_edges(hyper_map, nodes)

    # TODO: assemble_optigraph
    induced_graph = assemble_optigraph(nodes, edges) 
    return induced_graph
end

"""
    incident_edges(hyper_map::HyperMap, nodes::Vector{OptiNode})

Retrieve incident edges to a set of optinodes.

    incident_edges(hyper_map::HyperMap, node::OptiNode)

Retrieve incident edges to a single optinode.
"""
function incident_edges(hyper_map::HyperMap, nodes::Vector{OptiNode})
    hypernodes = Base.getindex.(Ref(hyper_map), nodes)
    edges = GOI.incident_edges(hyper_map.projected_graph, hypernodes)
    return get_mapped_elements(hyper_map, edges) #getindex.(Ref(hyper_map), incidentedges))
end

function incident_edges(hyper_map::HyperMap, node::OptiNode)
	return incident_edges(hyper_map, [node])
end


"""
    induced_edges(graph::OptiGraph, nodes::Vector{OptiNode})

Retrieve induced edges to a set of optinodes.
"""
function induced_edges(hyper_map::HyperMap, nodes::Vector{OptiNode})
    hypernodes = get_mapped_elements(hyper_map, nodes)
    induced = GOI.induced_edges(hyper_map.projected_graph, hypernodes)
    optiedges = get_mapped_elements(hyper_map, induced)
    return optiedges
end

"""
    identify_edges(hyper_map::HyperMap, node_vectors::Vector{Vector{OptiNode}})

Identify induced edges and edge separators from a vector of optinode partitions.

# Arguments
- `hyper_map::HyperMap`: A `HyperMap` obtained from `build_hypergraph`.
- `node_vectors::Vector{Vector{OptiNode}}`: A vector of vectors that contain `OptiNode`s.

# Returns
- partition_optiedges::Vector{Vector{OptiEdge}}: The `OptiEdge` vectors for each partition.
- cross_optiedges::Vector{OptiEdge}: A vector of optiedges that cross partitions.
"""
function identify_edges(hyper_map::HyperMap, node_vectors::Vector{Vector{OptiNode}})
    hypernode_vectors = get_mapped_elements.(Ref(hyper_map), node_vectors)
    partition_edges, cross_edges = GOI.identify_edges(
        hyper_map.projected_graph, 
        hypernode_vectors
    )
    partition_optiedges = get_mapped_elements.(Ref(hyper_map), partition_edges)
    cross_optiedges = get_mapped_elements(hyper_map, cross_edges)
    return partition_optiedges, cross_optiedges
end

"""
    identify_nodes(hyper_map::HyperMap, node_vectors::Vector{Vector{OptiEdge}})

Identify induced nodes and node separators from a vector of optiedge partitions.
"""
function identify_nodes(hyper_map::HyperMap, edge_vectors::Vector{Vector{OptiEdge}})
    hyperedge_vectors = get_mapped_elements.(Ref(hyper_map), edge_vectors)
    partition_nodes, cross_nodes = GOI.identify_nodes(
        hyper_map.projected_graph, 
        hyperedge_vectors
    )
    partition_optinodes = get_mapped_elements.(Ref(hyper_map), partition_nodes)
    cross_optinodes = get_mapped_elements(hyper_map, cross_nodes)
    return partition_optinodes, cross_optinodes
end

"""
    neighborhood(
        hyper_map::HyperMap, 
        nodes::Vector{OptiNode}, 
        distance::Int64
    )::Vector{OptiNode}

Return the optinodes within `distance` of the given `nodes` in the optigraph `graph`.
"""
function neighborhood(hyper_map::HyperMap, nodes::Vector{OptiNode}, distance::Int64)
    vertices = get_mapped_elements(hyper_map, nodes)
    new_nodes = GOI.neighborhood(hyper_map.projected_graph, vertices, distance)
    return get_mapped_elements(hyper_map, new_nodes) #getindex.(Ref(hyper_map), new_nodes)
end

"""
    expand(hyper_map::HyperMap, subgraph::OptiGraph, distance::Int64)

Return a new expanded subgraph given the optigraph `graph` and an existing subgraph `subgraph`.
The returned subgraph contains the expanded neighborhood within `distance` of the given `subgraph`.
"""
function expand(hyper_map::HyperMap, subgraph::OptiGraph, distance::Int64)
    nodes = all_nodes(subgraph)
    new_optinodes = neighborhood(hyper_map, nodes, distance)
    new_optiedges = induced_edges(hyper_map, new_optinodes)
    expanded_subgraph = assemble_optigraph(new_optinodes, new_optiedges)
    return expanded_subgraph
end
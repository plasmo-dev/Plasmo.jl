"""
    Graphs.all_neighbors(graph::OptiGraph, node::OptiNode)

Retrieve the optinode neighbors of `node` in the optigraph `graph`.  
Uses an underlying hypergraph to query for neighbors.
"""
function Graphs.all_neighbors(proj_map::ProjectionMap, node::OptiNode)
    vertex = proj_map[node]
    neighbors = Graphs.all_neighbors(proj_map.projected_graph, vertex)
    return getindex.(Ref(proj_map), neighbors)
end

"""
    Graphs.induced_subgraph(graph::OptiGraph, nodes::Vector{OptiNode})

Create an induced subgraph of optigraph given a vector of optinodes.
"""
function Graphs.induced_subgraph(proj_map::ProjectionMap, nodes::Vector{OptiNode})
    edges = induced_edges(proj_map, nodes)

    # TODO: assemble_optigraph
    induced_graph = assemble_optigraph(nodes, edges) 
    return induced_graph
end

"""
    incident_edges(graph::OptiGraph, nodes::Vector{OptiNode})

Retrieve incident edges to a set of optinodes.

    incident_edges(graph::OptiGraph, node::OptiNode)

Retrieve incident edges to a single optinode.
"""
function incident_edges(proj_map::ProjectionMap, nodes::Vector{OptiNode{OptiGraph}})
    hypernodes = Base.getindex.(Ref(proj_map), nodes)
    edges = GOI.incident_edges(proj_map.projected_graph, hypernodes)
    return get_mapped_elements(proj_map, edges) #getindex.(Ref(hyper_map), incidentedges))
end

function incident_edges(proj_map::ProjectionMap, node::OptiNode)
	return incident_edges(proj_map, [node])
end


# """
#     induced_edges(graph::OptiGraph, nodes::Vector{OptiNode})

# Retrieve induced edges to a set of optinodes.
# """
# function induced_edges(graph::OptiGraph, nodes::Vector{OptiNode})
#     _init_graph_backend(graph)
#     hypergraph, hyper_map = Plasmo.graph_backend_data(graph)
#     hypernodes = getindex.(Ref(hyper_map), nodes)
#     inducededges = induced_edges(hypergraph, hypernodes)
#     opti_edges = convert(Vector{OptiEdge}, getindex.(Ref(hyper_map), inducededges))
#     return opti_edges
# end

# """
#     identify_edges(graph::OptiGraph, node_vectors::Vector{Vector{OptiNode}})

# Identify induced edges and edge separators from a vector of optinode partitions.
# """
# function identify_edges(graph::OptiGraph, node_vectors::Vector{Vector{OptiNode}})
#     _init_graph_backend(graph)
#     hypergraph, hyper_map = Plasmo.graph_backend_data(graph)
#     hypernode_vectors = [getindex.(Ref(hyper_map), nodes) for nodes in node_vectors]
#     part_edges, cross_edges = identify_edges(hypergraph, hypernode_vectors)
#     link_part_edges = [getindex.(Ref(hyper_map), edges) for edges in part_edges]
#     link_cross_edges = getindex.(Ref(hyper_map), cross_edges)
#     return link_part_edges, link_cross_edges
# end

# """
#     identify_nodes(graph::OptiGraph, node_vectors::Vector{Vector{OptiEdge}})

# Identify induced nodes and node separators from a vector of optiedge partitions.
# """
# function identify_nodes(graph::OptiGraph, edge_vectors::Vector{Vector{OptiEdge}})
#     _init_graph_backend(graph)
#     hypergraph, hyper_map = Plasmo.graph_backend_data(graph)
#     hyperedge_vectors = [getindex.(Ref(hyper_map), edges) for edges in edge_vectors]
#     part_nodes, cross_nodes = identify_nodes(hypergraph, hyperedge_vectors)
#     part_optinodes = [getindex.(Ref(hyper_map), nodes) for nodes in part_nodes]
#     cross_optinodes = getindex.(Ref(hyper_map), cross_nodes)
#     return part_optinodes, cross_optinodes
# end

# """
#     neighborhood(graph::OptiGraph, nodes::Vector{OptiNode}, distance::Int64)::Vector{OptiNode})

# Return the optinodes within `distance` of the given `nodes` in the optigraph `graph`.
# """
# function neighborhood(graph::OptiGraph, nodes::Vector{OptiNode}, distance::Int64)
#     _init_graph_backend(graph)
#     hypergraph, hyper_map = Plasmo.graph_backend_data(graph)
#     vertices = getindex.(Ref(hyper_map), nodes)
#     new_nodes = neighborhood(hypergraph, vertices, distance)
#     return getindex.(Ref(hyper_map), new_nodes)
# end

# """
#     expand(graph::OptiGraph, subgraph::OptiGraph, distance::Int64)

# Return a new expanded subgraph given the optigraph `graph` and an existing subgraph `subgraph`.
# The returned subgraph contains the expanded neighborhood within `distance` of the given `subgraph`.
# """
# function expand(graph::OptiGraph, subgraph::OptiGraph, distance::Int64)
#     _init_graph_backend(graph)
#     hypergraph, hyper_map = Plasmo.graph_backend_data(graph)

#     nodes = all_nodes(subgraph)
#     hypernodes = getindex.(Ref(hyper_map), nodes)

#     new_nodes = neighborhood(hypergraph, hypernodes, distance)
#     new_edges = induced_edges(hypergraph, new_nodes)

#     new_optinodes = getindex.(Ref(hyper_map), new_nodes)
#     new_optiedges = getindex.(Ref(hyper_map), new_edges)
#     new_subgraph = OptiGraph(new_optinodes, new_optiedges)

#     return new_subgraph
# end
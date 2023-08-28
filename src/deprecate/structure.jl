
"""
    local_edges(graph::OptiGraph)::Vector{OptiEdge}

Query the edges in `graph` that connect nodes within the graph, but not subgraphs
"""
function local_edges(graph::OptiGraph)
    return induced_edges(graph, optinodes(graph))
end

"""
    hierarchical_edges(graph::OptiGraph)::Vector{OptiEdge}

Query the edges in `graph` that connect its local nodes to nodes in its subgraphs.
"""
function hierarchical_edges(graph::OptiGraph)
    return incident_edges(graph, optinodes(graph))
end

"""
    cross_edges(graph::OptiGraph)::Vector{OptiEdge}

Query the edges in `graph` that connect nodes between subgraphs.
"""
function cross_edges(graph::OptiGraph)
    iedges = Plasmo.identify_edges(graph, optinodes.(subgraphs(graph)))
    return iedges[2]
end

"""
    global_edges(graph::OptiGraph)::Vector{OptiEdge}

Query the edges in `graph` that are both hierarchical and cross subgraphs
"""
function global_edges(graph::OptiGraph)
    return intersect(hierarchical_edges(graph), cross_edges(graph))
end

"""
    cross_edges_not_global(graph::OptiGraph)::Vector{OptiEdge}

Query the edges in `graph` that cross subgraphs, but are not global
"""
function cross_edges_not_global(graph::OptiGraph)
    return setdiff(cross_edges(graph), global_edges(graph))
end

"""
    hierarchical_edges_not_global(graph::OptiGraph)::Vector{OptiEdge}

Query the edges in `graph` that are hierarchical, but are not global
"""
function hierarchical_edges_not_global(graph::OptiGraph)
    return setdiff(hierarchical_edges(graph), global_edges(graph))
end

"""
	has_hierarchical_edges(graph::OptiGraph)

Return whether `graph` contains hierarchical edges
"""
has_hierarchical_edges(graph::OptiGraph) = length(hierarchical_edges(graph)) > 0

"""
    has_cross_edges(graph::OptiGraph)

Return whether `graph` contains hierarchical edges
"""
has_cross_edges(graph::OptiGraph) = length(cross_edges(graph)) > 0

"""
    has_global_edges(graph::OptiGraph)

Return whether `graph` contains global edges
"""
has_global_edges(graph::OptiGraph) = length(global_edges(graph)) > 0

"""
	graph_depth(graph::OptiGraph)::Intger

Return the total number of subgraph layers in `graph`.
"""
function graph_depth(graph::OptiGraph)
    depth = 0
    if has_subgraphs(graph)
        depth += 1
        depth += _subgraph_depth(subgraphs(graph))
    end
    return depth
end

#recursively check subgraph depth
function _subgraph_depth(subgraphs::Vector{OptiGraph})
    depth = 0
    if any((g) -> has_subgraphs(g), subgraphs)
        depth += 1
        for sub in subgraphs
            depth += _subgraph_depth(subgraphs(sub))
        end
    end
    return depth
end

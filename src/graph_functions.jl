#Graph Interface for an OptiGraph.  An OptiGraph backend is a hypergraph.  We store the backend to avoid re-creating a hypergraph everytime
#a graph function is called.  Currently, backend is not kept in sync with optigraph, so we hit _init_graph_backend which catches
#updates using a flag when new nodes or edges are added.

#Set graph backend
function set_graph_backend(graph::OptiGraph)
    hypergraph,hypermap = hyper_graph(graph)
    graph.graph_backend = HyperGraphBackend(hypergraph,hypermap,false)
end
set_graph_backend(graph::OptiGraph,backend::HyperGraphBackend) = graph.graph_backend = backend

graph_backend(graph::OptiGraph) = (graph.graph_backend)
function graph_backend_data(graph::OptiGraph)
    return graph.graph_backend.hypergraph,graph.graph_backend.hyper_map
end
function _init_graph_backend(graph::OptiGraph)
    if graph.graph_backend == nothing
        set_graph_backend(graph)
    elseif graph.graph_backend.update_backend == true
        set_graph_backend(graph)
    end
    return nothing
end

"""
    LightGraphs.all_neighbors(graph::OptiGraph,node::OptiNode)

Retrieve the optinode neighbors of `node` in the optigraph `graph`.  Uses an underlying hypergraph to query for neighbors.
"""
function LightGraphs.all_neighbors(graph::OptiGraph,node::OptiNode)
    _init_graph_backend(graph)
    lightgraph,graph_map = graph_backend_data(graph)
    vertex = graph_map[node]
    neighbors = LightGraphs.all_neighbors(lightgraph,vertex)
    return getindex.(Ref(graph_map),neighbors)
end

"""
    LightGraphs.induced_subgraph(graph::OptiGraph,nodes::Vector{OptiNode})

Create an induced subgraph of optigraph given a vector of optinodes.
"""
function LightGraphs.induced_subgraph(graph::OptiGraph,nodes::Vector{OptiNode})
    _init_graph_backend(graph)
    edges = induced_edges(graph,nodes)
    subgraph = OptiGraph(nodes,edges)
    return subgraph
end

"""
    incident_edges(graph::OptiGraph,nodes::Vector{OptiNode})

Retrieve incident edges to a set of optinodes.

    incident_edges(graph::OptiGraph,node::OptiNode)

Retrieve incident edges to a single optinode.
"""
function incident_edges(graph::OptiGraph,nodes::Vector{OptiNode})
    _init_graph_backend(graph)
    hypergraph,hyper_map = Plasmo.graph_backend_data(graph)
    hypernodes = convert(Vector{HyperNode},getindex.(Ref(hyper_map),nodes))
    incidentedges = incident_edges(hypergraph,hypernodes)
    return convert(Vector{OptiEdge},getindex.(Ref(hyper_map),incidentedges))
end
incident_edges(graph::OptiGraph,node::OptiNode) = incident_edges(graph,[node])

"""
    induced_edges(graph::OptiGraph,nodes::Vector{OptiNode})

Retrieve induced edges to a set of optinodes.
"""
function induced_edges(graph::OptiGraph,nodes::Vector{OptiNode})
    _init_graph_backend(graph)
    hypergraph,hyper_map = Plasmo.graph_backend_data(graph)
    hypernodes = getindex.(Ref(hyper_map),nodes)
    inducededges = induced_edges(hypergraph,hypernodes)
    return getindex.(Ref(hyper_map),inducededges)
end

"""
    identify_edges(graph::OptiGraph,node_vectors::Vector{Vector{OptiNode}})

Identify induced edges and edge separators from a vector of optinode partitions.
"""
function identify_edges(graph::OptiGraph,node_vectors::Vector{Vector{OptiNode}})
    _init_graph_backend(graph)
    hypergraph,hyper_map = Plasmo.graph_backend_data(graph)
    hypernode_vectors = [getindex.(Ref(hyper_map),nodes) for nodes in node_vectors]
    part_edges,cross_edges = identify_edges(hypergraph,hypernode_vectors)
    link_part_edges = [getindex.(Ref(hyper_map),edges) for edges in part_edges]
    link_cross_edges = getindex.(Ref(hyper_map),cross_edges)
    return link_part_edges,link_cross_edges
end

"""
    identify_nodes(graph::OptiGraph,node_vectors::Vector{Vector{OptiEdge}})

Identify induced nodes and node separators from a vector of optiedge partitions.
"""
function identify_nodes(graph::OptiGraph,edge_vectors::Vector{Vector{OptiEdge}})
    _init_graph_backend(graph)
    hypergraph,hyper_map = Plasmo.graph_backend_data(graph)
    hyperedge_vectors = [getindex.(Ref(hyper_map),edges) for edges in edge_vectors]
    part_nodes,cross_nodes = identify_nodes(hypergraph,hyperedge_vectors)
    part_optinodes = [getindex.(Ref(hyper_map),nodes) for nodes in part_nodes]
    cross_optinodes = getindex.(Ref(hyper_map),cross_nodes)
    return part_optinodes,cross_optinodes
end

"""
    neighborhood(graph::OptiGraph,nodes::Vector{OptiNode},distance::Int64)::Vector{OptiNode})

Return the optinodes within `distance` of the given `nodes` in the optigraph `graph`.
"""
function neighborhood(graph::OptiGraph,nodes::Vector{OptiNode},distance::Int64)
    _init_graph_backend(graph)
    hypergraph,hyper_map = Plasmo.graph_backend_data(graph)
    vertices = getindex.(Ref(hyper_map),nodes)
    new_nodes = neighborhood(hypergraph,vertices,distance)
    return getindex.(Ref(hyper_map),new_nodes)
end

"""
    expand(graph::OptiGraph,subgraph::OptiGraph,distance::Int64)

Return a new expanded subgraph given the optigraph `graph` and an existing subgraph `subgraph`.
The returned subgraph contains the expanded neighborhood within `distance` of the given `subgraph`.
"""
function expand(graph::OptiGraph,subgraph::OptiGraph,distance::Int64)
    _init_graph_backend(graph)
    hypergraph,hyper_map = Plasmo.graph_backend_data(graph)

    nodes = all_nodes(subgraph)
    hypernodes = getindex.(Ref(hyper_map),nodes)

    new_nodes = neighborhood(hypergraph,hypernodes,distance)
    new_edges =  induced_edges(hypergraph,new_nodes)

    new_optinodes = getindex.(Ref(hyper_map),new_nodes)
    new_optiedges = getindex.(Ref(hyper_map),new_edges)
    new_subgraph = OptiGraph(new_optinodes,new_optiedges)

    return new_subgraph
end

"""
    hierarchical_edges(graph::OptiGraph)::Vector{OptiEdge}

Query the edges in `graph` that connect its local nodes to nodes in its subgraphs.
"""
function hierarchical_edges(graph::OptiGraph)
    return incident_edges(graph,getnodes(graph))
end

"""
    linking_edges(graph::OptiGraph)::Vector{OptiEdge}

Query the edges in `graph` that connect nodes within the graph or between subgraphs.
"""
function linking_edges(graph::OptiGraph)
    return setdiff(getedges(graph),incident_edges(graph,getnodes(graph)))
end

#TODO: try forwarding methods this way
# macro forward_graph_node_method(func)
#     return quote
#         function $(func)(graph::OptiGraph,node::OptiNode)
#             Plasmo._init_graph_backend(graph)
#             hypergraph,hyper_map = Plasmo.graph_backend_data(graph)
#             vertex = hyper_map[node]
#             output = $func(hypergraph,vertex)
#             return getindex.(Ref(hyper_map),output)
#         end
#     end
# end
#@forward_graph_node_method(LightGraphs.all_neighbors)

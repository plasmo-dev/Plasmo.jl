"""
    hyper_graph(graph::OptiGraph)

Retrieve a hypergraph representation of the optigraph `graph`. Returns a [`HyperGraph`](@ref) object, as well as a dictionary
that maps hypernodes and hyperedges to the original optinodes and optiedges.
"""
function hyper_graph(graph::OptiGraph)
    hypergraph = HyperGraph()
    hyper_map = Dict()  #two-way mapping from hypergraph nodes to optinodes and link_edges

    for node in all_nodes(graph)
        hypernode = add_node!(hypergraph)
        hyper_map[hypernode] = node
        hyper_map[node] = hypernode
    end

    for edge in all_edges(graph)
        nodes = edge.nodes
        hypernodes = [hyper_map[optinode] for optinode in nodes]
        if length(hypernodes) >= 2
            hyperedge = add_hyperedge!(hypergraph,hypernodes...)
            hyper_map[hyperedge] = edge
            hyper_map[edge] = hyperedge
        end
    end

    return hypergraph,hyper_map
end
@deprecate gethypergraph hyper_graph
"""
    clique_graph(graph::OptiGraph)

Retrieve a standard graph representation of the optigraph `graph`. Returns a [`LightGraphs.Graph`](@ref) object, as well as a dictionary
that maps vertices and edges to the optinodes and optiedges.
"""
function clique_graph(optigraph::OptiGraph)
    graph = LightGraphs.Graph()
    graph_map = Dict()

    for optinode in all_nodes(optigraph)
        add_vertex!(graph)
        vertex = nv(graph)
        graph_map[vertex] = optinode
        graph_map[optinode] = vertex
    end

    #Optiedges
    for edge in all_edges(optigraph)
        graph_map[edge] = []
        nodes = edge.nodes
        edge_vertices = [graph_map[optinode] for optinode in nodes]
        for i = 1:length(edge_vertices)
            vertex_from = edge_vertices[i]
            other_vertices = edge_vertices[i+1:end]
            for j = 1:length(other_vertices)
                vertex_to = other_vertices[j]
                inserted = LightGraphs.add_edge!(graph,vertex_from,vertex_to)
                new_edge = LightGraphs.SimpleEdge(sort([vertex_from,vertex_to])...)
                if inserted #new simple edge was created
                    graph_map[new_edge] = edge
                    push!(graph_map[edge],new_edge)
                end
            end
        end
    end
    return graph,graph_map
end
@deprecate getcliquegraph clique_graph

"""
    bipartite_graph(graph::OptiGraph)

Create a bipartite graph using a optigraph
"""
function bipartite_graph(optigraph::OptiGraph)
    graph = BipartiteGraph()
    graph_map = Dict()

    for optinode in all_nodes(optigraph)
        LightGraphs.add_vertex!(graph,bipartite = 1)
        node_vertex = nv(graph)
        graph_map[node_vertex] = optinode
        graph_map[optinode] = node_vertex
    end

    for edge in all_edges(optigraph)
        LightGraphs.add_vertex!(graph,bipartite = 2)
        edge_vertex = nv(graph)
        graph_map[edge] = edge_vertex
        graph_map[edge_vertex] = edge
        nodes = edge.nodes
        edge_vertices = [graph_map[optinode] for optinode in nodes]
        for node_vertex in edge_vertices
            LightGraphs.add_edge!(graph,edge_vertex,node_vertex)
        end
    end
    return graph,graph_map
end


#TODO
"""
    edge_clique_graph(graph::OptiGraph)

Retrieve the line graph clique representation of the optigraph `graph`. Returns a [`LightGraphs.Graph`](@ref) object, as well as a dictionary
that maps vertices and edges to the optinodes and optiedges. The dual cliquegraph inverts nodes and edges to allow edge partitioning.
"""
function edge_clique_graph(optigraph::OptiGraph)
end


#TODO
"""
    edge_hypergraph(graph::OptiGraph)

Retrieve a hypergraph representation of the optigraph `graph`. Returns a [`HyperGraph`](@ref) object, as well as a dictionary
that maps hypernodes and hyperedges to the original optinodes and optiedges.
"""
function edge_hyper_graph(graph::OptiGraph)
    hypergraph = HyperGraph()
    hyper_map = Dict()

    for edge in all_edges(graph)
        hypernode = add_node!(hypergraph)
        hyper_map[hypernode] = edge
        hyper_map[edge] = hypernode
    end

    #TODO: get nodes that connect edges. Some optinodes won't have a mapping to the edge hyper graph


    return hypergraph,hyper_map
end

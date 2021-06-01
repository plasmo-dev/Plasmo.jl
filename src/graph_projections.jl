"""
    hyper_graph(graph::OptiGraph)

Retrieve a hypergraph representation of the optigraph `graph`. Returns a [`HyperGraph`](@ref) object, as well as a dictionary
that maps hypernodes and hyperedges to the original optinodes and optiedges.
"""
function hyper_graph(optigraph::OptiGraph)
    hypergraph = HyperGraph()
    hyper_map = Dict()  #two-way mapping from hypergraph nodes to optinodes and link_edges

    for node in all_nodes(optigraph)
        hypernode = add_node!(hypergraph)
        hyper_map[hypernode] = node
        hyper_map[node] = hypernode
    end

    for edge in all_edges(optigraph)
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
    #graph = LightGraphs.Graph()
    graph = CliqueGraph()
    graph_map = Dict()

    #optinodes
    for optinode in all_nodes(optigraph)
        add_vertex!(graph)
        vertex = nv(graph)
        graph_map[vertex] = optinode
        graph_map[optinode] = vertex
    end

    #Add coupling
    for edge in all_edges(optigraph)
        #graph_map[edge] = []
        nodes = edge.nodes
        edge_vertices = [graph_map[optinode] for optinode in nodes]
        for i = 1:length(edge_vertices)
            vertex_from = edge_vertices[i]
            other_vertices = edge_vertices[i+1:end]
            for j = 1:length(other_vertices)
                vertex_to = other_vertices[j]
                inserted = LightGraphs.add_edge!(graph,vertex_from,vertex_to)
                # new_edge = LightGraphs.SimpleEdge(sort([vertex_from,vertex_to])...)
                # if inserted #new simple edge was created
                #     graph_map[new_edge] = edge
                #     push!(graph_map[edge],new_edge)
                # end
            end
        end
    end
    return graph,graph_map
end
@deprecate getcliquegraph clique_graph

"""
    edge_graph(optigraph::OptiGraph)

Retrieve the edge-graph representation of `optigraph`. This is sometimes called the line graph of a hypergraph.
Returns a [`LightGraphs.Graph`](@ref) object, as well as a dictionary that maps vertices and edges to the optinodes and optiedges.
"""
function edge_graph(optigraph::OptiGraph)
    graph = LightGraphs.Graph()
    graph_map = Dict()

    #optiedge => vertex
    for optiedge in all_edges(optigraph)
        add_vertex!(graph)
        vertex = nv(graph)
        graph_map[vertex] = optiedge
        graph_map[optiedge] = vertex
    end

    #add coupling
    edge_array = all_edges(optigraph)
    for i in 1:(num_all_optiedges(optigraph)-1)
        for j in i+1:num_all_optiedges(optigraph)
            e1 = edge_array[i]
            e2 = edge_array[j]
            if !isempty(intersect(e1.nodes,e2.nodes))
                LightGraphs.add_edge!(graph, graph_map[e1], graph_map[e2])
            end
        end
    end
    return graph, graph_map
end

"""
    edge_hyper_graph(graph::OptiGraph)

Retrieve an edge-hypergraph representation of the optigraph `graph`. Returns a [`HyperGraph`](@ref) object, as well as a dictionary
that maps hypernodes and hyperedges to the original optinodes and optiedges. This is also called the dual-hypergraph representation of a hypergraph.
"""
function edge_hyper_graph(optigraph::OptiGraph)
    hypergraph = HyperGraph()
    hyper_map = Dict()

    #optiedges are hypernodes
    for edge in all_edges(optigraph)
        hypernode = add_node!(hypergraph)
        hyper_map[hypernode] = edge
        hyper_map[edge] = hypernode
    end

    #add hyperedge for each optinode that is shared across multiple optiedges
    for node in all_nodes(optigraph)
        hyperedges = incident_edges(optigraph,node)
        if length(hyperedges) >= 2
            dual_nodes = [hyper_map[edge] for edge in hyperedges]
            add_hyperedge!(hypergraph,dual_nodes...)
        end
    end

    return hypergraph,hyper_map
end

"""
    bipartite_graph(optigraph::OptiGraph)

Create a bipartite graph representation from `optigraph`.  The bipartite graph contains two sets of vertices corresponding to optinodes and optiedges respectively.
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

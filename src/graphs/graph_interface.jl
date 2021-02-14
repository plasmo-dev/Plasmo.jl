#Create a hypergraph object from a ModelGraph.  Return the hypergraph and a mapping of hypergraph nodes and edges to optigraph optinodes and optiedges.
#A hypergraph has topology functions and partitioning interfaces.

#Create a hypergraph representation of a optigraph
"""
    gethypergraph(graph::OptiGraph)

Retrieve a hypergraph representation of the optigraph `graph`. Returns a [`HyperGraph`](@ref) object, as well as a dictionary
that maps hypernodes and hyperedges to the original optinodes and optiedges.
"""
function gethypergraph(graph::OptiGraph)
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

"""
    getcliquegraph(graph::OptiGraph)

Retrieve a standard graph representation of the optigraph `graph`. Returns a [`LightGraphs.Graph`](@ref) object, as well as a dictionary
that maps vertices and edges to the optinodes and optiedges.
"""
function getcliquegraph(optigraph::OptiGraph)
    graph = LightGraphs.Graph()
    graph_map = Dict()

    for optinode in all_nodes(optigraph)
        add_vertex!(graph)
        vertex = nv(graph)
        graph_map[vertex] = optinode
        graph_map[optinode] = vertex
    end

    #HyperEdges
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

#Create a bipartite graph using a optigraph
function getbipartitegraph(graph::OptiGraph)
end

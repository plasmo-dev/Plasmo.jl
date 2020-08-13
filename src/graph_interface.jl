#Create a hypergraph object from a ModelGraph.  Return the hypergraph and a mapping of hypergraph nodes and edges to optigraph optinodes and optiedges.
#A hypergraph has topology functions and partitioning interfaces.

#Create a hypergraph representation of a optigraph
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

#Create a lightgraph Graph using a optigraph
function getcliquegraph(graph::OptiGraph)
end

#Create a bipartite graph using a optigraph
function getbipartitegraph(graph::OptiGraph)
end

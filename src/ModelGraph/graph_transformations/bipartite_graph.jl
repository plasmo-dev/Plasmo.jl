mutable struct BipartiteGraph <: AbstractPlasmoGraph
    basegraph::BasePlasmoGraph                   #Model graph structure.  Put constraint references on edges
end

BipartiteGraph() = BipartiteGraph(BasePlasmoGraph(LightGraphs.Graph))

create_node(graph::BipartiteGraph) = BasePlasmoNode()
create_edge(graph::BipartiteGraph) = BasePlasmoEdge()

function string(graph::BipartiteGraph)
    "Bipartite Graph\ngraph_id: "*string(getlabel(graph))*"\nnodes:"*string((length(getnodes(graph))))
end

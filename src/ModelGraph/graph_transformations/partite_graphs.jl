mutable struct BipartiteGraph <: AbstractPlasmoGraph
    basegraph::BasePlasmoGraph
    part1::Vector{Int64}   #partition 1 of the bipartite graph
    part2::Vector{Int64}   #partition 2 of the bipartite graph
end

BipartiteGraph() = BipartiteGraph(BasePlasmoGraph(LightGraphs.Graph),Int64[],Int64[])

create_node(graph::BipartiteGraph) = BasePlasmoNode()
create_edge(graph::BipartiteGraph) = BasePlasmoEdge()

function string(graph::BipartiteGraph)
    "Bipartite Graph\ngraph_id: "*string(getlabel(graph))*"\nnodes:"*string((length(getnodes(graph))))
end

mutable struct UnipartiteGraph <: AbstractPlasmoGraph
    basegraph::BasePlasmoGraph
    v_weights::Dict{Int64,Int64}                     #vertex weights
    e_weights::Dict{LightGraphs.AbstractEdge,Int64}  #edge weights
end

UnipartiteGraph() = UnipartiteGraph(BasePlasmoGraph(LightGraphs.Graph),Dict{BasePlasmoNode,Int64}(),Dict{BasePlasmoNode,Int64}())

create_node(graph::UnipartiteGraph) = BasePlasmoNode()
create_edge(graph::UnipartiteGraph) = BasePlasmoEdge()

function string(graph::UnipartiteGraph)
    "Unipartite Graph\ngraph_id: "*string(getlabel(graph))*"\nnodes:"*string((length(getnodes(graph))))
end

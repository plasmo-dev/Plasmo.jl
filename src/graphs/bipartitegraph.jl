"""
    BipartiteGraph

A simple bipartite type.  Tracks vertex sets of the bipartite graph.
"""
mutable struct BipartiteGraph <: LightGraphs.AbstractGraph{Int64}
    graph::LightGraphs.Graph
    vertexset1::Vector{Int64}
    vertexset2::Vector{Int64}
end

BipartiteGraph() = BipartiteGraph(LightGraphs.Graph(),Vector{Int64}(),Vector{Int64}())


function LightGraphs.add_vertex!(graph::BipartiteGraph;bipartite = 1)
    added = LightGraphs.add_vertex!(graph.lightgraph)
    vertex = nv(graph.lightgraph)
    if bipartite == 1
        push!(vertexset1,vertex)
    else
        @assert bipartite == 2
        push!(vertexset1,vertex)
    end
    return added
end

LightGraphs.add_edge!(graph::BipartiteGraph,from::Int64,to::Int64) = LightGraphs.add_edge!(graph,from,int)

LightGraphs.edges(graph::BipartiteGraph) = LightGraph.edges(graph.lightgraph)
LightGraphs.edgetype(graph::BipartiteGraph) = LightGraphs.SimpleGraphs.SimpleEdge{Int64}
LightGraphs.has_edge(graph::BipartiteGraph,from::Int64,to::Int64) = LightGraphs.has_edge(graph.lightgraph,from,to)


LightGraphs.has_vertex(graph::BipartiteGraph, v::Integer) = LightGraphs.has_vertex(graph.lightgraph,v)
LightGraphs.is_directed(graph::BipartiteGraph) = false
LightGraphs.is_directed(::Type{BipartiteGraph}) = false
LightGraphs.ne(graph::BipartiteGraph) = LightGraphs.ne(graph.lightgraph)
LightGraphs.nv(graph::BipartiteGraph) = LightGraphs.nv(graph.lightgraph)
LightGraphs.vertices(graph::BipartiteGraph) = LightGraphs.vertices(graph.lightgraph)

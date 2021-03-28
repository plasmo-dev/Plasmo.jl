"""
    BipartiteGraph

A simple bipartite graph.  Contains two vertex sets to enforce bipartite structure.
"""
mutable struct BipartiteGraph <: LightGraphs.AbstractGraph{Int64}
    graph::LightGraphs.Graph
    vertexset1::Vector{Int64}
    vertexset2::Vector{Int64}
end

BipartiteGraph() = BipartiteGraph(LightGraphs.Graph(),Vector{Int64}(),Vector{Int64}())


function LightGraphs.add_vertex!(bgraph::BipartiteGraph;bipartite = 1)
    added = LightGraphs.add_vertex!(bgraph.graph)
    vertex = nv(bgraph.graph)
    if bipartite == 1
        push!(bgraph.vertexset1,vertex)
    else
        @assert bipartite == 2
        push!(bgraph.vertexset2,vertex)
    end
    return added
end

#Edges must connect nodes in different vertex sets
function LightGraphs.add_edge!(bgraph::BipartiteGraph,from::Int64,to::Int64)
    length(intersect((from,to),bgraph.vertexset1)) == 1 || error("$from and $to must be in separate vertex sets")
    return LightGraphs.add_edge!(bgraph.graph,from,to)
end

LightGraphs.edges(bgraph::BipartiteGraph) = LightGraph.edges(bgraph.graph)
LightGraphs.edgetype(bgraph::BipartiteGraph) = LightGraphs.SimpleGraphs.SimpleEdge{Int64}

LightGraphs.has_edge(bgraph::BipartiteGraph,from::Int64,to::Int64) = LightGraphs.has_edge(bgraph.graph,from,to)
LightGraphs.has_vertex(bgraph::BipartiteGraph, v::Integer) = LightGraphs.has_vertex(bgraph.graph,v)

LightGraphs.is_directed(bgraph::BipartiteGraph) = false
LightGraphs.is_directed(::Type{BipartiteGraph}) = false

LightGraphs.ne(bgraph::BipartiteGraph) = LightGraphs.ne(bgraph.graph)
LightGraphs.nv(bgraph::BipartiteGraph) = LightGraphs.nv(bgraph.graph)
LightGraphs.vertices(bgraph::BipartiteGraph) = LightGraphs.vertices(bgraph.graph)

#TODO: try forwarding methods this way
macro forward_bipartite_method(func)
    return quote
        function $(func)(bgraph::BipartiteGraph,args...)
            output = $func(bgraph.graph,args...)
            return output
        end
    end
end
@forward_bipartite_method(LightGraphs.all_neighbors)

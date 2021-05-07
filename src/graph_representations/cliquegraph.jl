"""
    CliqueGraph

A simple Graph created from a HyperGrpah.  Normally could just be a LightGraph, but we want to avoid type-piracy on the partition functions.
"""
mutable struct CliqueGraph <: LightGraphs.AbstractGraph{Int64}
    graph::LightGraphs.Graph
    edge_weights::Vector
end

CliqueGraph() = BipartiteGraph(LightGraphs.Graph(),Vector{Int64}(),Vector{Int64}())


function LightGraphs.add_vertex!(cgraph::CliqueGraph)
    added = LightGraphs.add_vertex!(cgraph.graph)
    return added
end

function LightGraphs.add_edge!(cgraph::CliqueGraph,from::Int64,to::Int64)
    return LightGraphs.add_edge!(cgraph.graph,from,to)
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


# TODO: try forwarding methods this way.  Causes ambiguous method calls....
macro forward_clique_graph_method(func)
    return quote
        function $(func)(cgraph::BipartiteGraph,args...)
            output = $func(cgraph.graph,args...)
            return output
        end
    end
end
@forward_clique_graph_method(LightGraphs.all_neighbors)

"""
    CliqueGraph

A simple Graph created from an OptiGraph.  Normally could just be a LightGraph, but we want to avoid type-piracy on the partition functions.
"""
mutable struct CliqueGraph <: LightGraphs.AbstractGraph{Int64}
    graph::LightGraphs.Graph
end

CliqueGraph() = CliqueGraph(LightGraphs.Graph())


function LightGraphs.add_vertex!(cgraph::CliqueGraph)
    added = LightGraphs.add_vertex!(cgraph.graph)
    return added
end

function LightGraphs.add_edge!(cgraph::CliqueGraph,from::Int64,to::Int64)
    return LightGraphs.add_edge!(cgraph.graph,from,to)
end

LightGraphs.edges(cgraph::CliqueGraph) = LightGraphs.edges(cgraph.graph)
LightGraphs.edgetype(cgraph::CliqueGraph) = LightGraphs.SimpleGraphs.SimpleEdge{Int64}

LightGraphs.has_edge(cgraph::CliqueGraph,from::Int64,to::Int64) = LightGraphs.has_edge(cgraph.graph,from,to)
LightGraphs.has_vertex(cgraph::CliqueGraph, v::Integer) = LightGraphs.has_vertex(cgraph.graph,v)

LightGraphs.is_directed(cgraph::CliqueGraph) = false
LightGraphs.is_directed(::Type{CliqueGraph}) = false

LightGraphs.ne(cgraph::CliqueGraph) = LightGraphs.ne(cgraph.graph)
LightGraphs.nv(cgraph::CliqueGraph) = LightGraphs.nv(cgraph.graph)
LightGraphs.vertices(cgraph::CliqueGraph) = LightGraphs.vertices(cgraph.graph)


macro forward_clique_graph_method(func)
    return quote
        function $(func)(cgraph::Plasmo.CliqueGraph,args...)
            output = $(func)(cgraph.graph,args...)
            return output
        end
    end
end
@forward_clique_graph_method(LightGraphs.all_neighbors)
@forward_clique_graph_method(LightGraphs.incidence_matrix)

induced_elements(cgraph::CliqueGraph,partitions::Vector{Vector{Int64}}) = partitions

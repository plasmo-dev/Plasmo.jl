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

function LightGraphs.add_edge!(cgraph::CliqueGraph, from::Int64, to::Int64)
    return LightGraphs.add_edge!(cgraph.graph, from, to)
end

LightGraphs.edges(cgraph::CliqueGraph) = LightGraphs.edges(cgraph.graph)
LightGraphs.edgetype(cgraph::CliqueGraph) = LightGraphs.SimpleGraphs.SimpleEdge{Int64}

function LightGraphs.has_edge(cgraph::CliqueGraph, from::Int64, to::Int64)
    return LightGraphs.has_edge(cgraph.graph, from, to)
end
function LightGraphs.has_vertex(cgraph::CliqueGraph, v::Integer)
    return LightGraphs.has_vertex(cgraph.graph, v)
end

LightGraphs.is_directed(cgraph::CliqueGraph) = false
LightGraphs.is_directed(::Type{CliqueGraph}) = false

LightGraphs.ne(cgraph::CliqueGraph) = LightGraphs.ne(cgraph.graph)
LightGraphs.nv(cgraph::CliqueGraph) = LightGraphs.nv(cgraph.graph)
LightGraphs.vertices(cgraph::CliqueGraph) = LightGraphs.vertices(cgraph.graph)

function LightGraphs.all_neighbors(cgraph::CliqueGraph, idx::Integer)
    return LightGraphs.all_neighbors(cgraph.graph, idx)
end
function LightGraphs.incidence_matrix(cgraph::CliqueGraph)
    return LightGraphs.incidence_matrix(cgraph.graph)
end
induced_elements(cgraph::CliqueGraph, partitions::Vector{Vector{Int64}}) = partitions

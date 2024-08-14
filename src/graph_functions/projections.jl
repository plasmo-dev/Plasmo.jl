#  Copyright 2021, Jordan Jalving, Yankai Cao, Victor Zavala, and contributors
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at https://mozilla.org/MPL/2.0/.

abstract type AbstractProjectionType end

const GraphElement = Union{Int64,Graphs.AbstractEdge}

"""
    GraphProjection

A mapping between OptiGraph elements (nodes and edges) and elements in a graph projection. 
A graph projection can be for example a hypergraph, a bipartite graph
or a standard graph.
"""
mutable struct GraphProjection{GT<:Graphs.AbstractGraph,PT<:AbstractProjectionType}
    optigraph::OptiGraph
    projected_graph::GT
    projection_type::PT
    proj_to_opti_map::Dict{GraphElement,OptiElement}
    opti_to_proj_map::Dict{OptiElement,GraphElement}
end

function GraphProjection(
    optigraph::OptiGraph, projected_graph::GT, projection_type::PT
) where {GT<:Graphs.AbstractGraph,PT<:AbstractProjectionType}
    return GraphProjection(
        optigraph,
        projected_graph,
        projection_type,
        Dict{GraphElement,OptiElement}(),
        Dict{OptiElement,GraphElement}(),
    )
end

function Base.string(proj::GraphProjection)
    return "Graph Projection: $(proj.projection_type)"
end
Base.print(io::IO, proj::GraphProjection) = Base.print(io, Base.string(proj))
Base.show(io::IO, proj::GraphProjection) = Base.print(io, proj)

function Base.getindex(graph_map::GraphProjection, element::GraphElement)
    return graph_map.proj_to_opti_map[vertex]
end

function Base.setindex!(
    graph_map::GraphProjection, vertex::Union{Int64,Graphs.AbstractEdge}, value::OptiElement
)
    return graph_map.proj_to_opti_map[vertex] = value
end

function Base.getindex(graph_map::GraphProjection, element::OptiElement)
    return graph_map.opti_to_proj_map[element]
end

function Base.setindex!(
    graph_map::GraphProjection,
    element::OptiElement,
    value::Union{Int64,Graphs.AbstractEdge},
)
    return graph_map.opti_to_proj_map[element] = value
end

Base.broadcastable(graph_map::GraphProjection) = Ref(graph_map)

"""
    get_mapped_elements(proj_map::GraphProjection, elements::Vector{<:OptiElement})

Get the projected graph elements that correspond to the supplied optigraph elements. Note 
the use of `UnionAll` to catch vectors of either element.

    get_mapped_elements(proj_map::GraphProjection, elements::Vector{<:GraphElement})

Get the optiraph elements that correspond to the supplied projected graph elements. Note 
the use of `UnionAll` to catch vectors of either element.
"""
function get_mapped_elements(proj_map::GraphProjection, elements::Vector{<:OptiElement})
    return getindex.(Ref(proj_map.opti_to_proj_map), elements)
end

function get_mapped_elements(proj_map::GraphProjection, elements::Vector{<:GraphElement})
    return getindex.(Ref(proj_map.proj_to_opti_map), elements)
end

struct HyperGraphProjectionType <: AbstractProjectionType end

"""
    hyper_projection(graph::OptiGraph)

Retrieve a hypergraph representation of the optigraph `graph`. Returns 
a [`GraphProjection`](@ref) that maps elements between the optigraph and the projected graph.
"""
function hyper_projection(graph::OptiGraph)
    hypergraph = GOI.HyperGraph()
    projection = GraphProjection(graph, hypergraph, HyperGraphProjectionType())
    for node in all_nodes(graph)
        hypernode = Graphs.add_vertex!(hypergraph)
        projection[hypernode] = node
        projection[node] = hypernode
    end
    for edge in all_edges(graph)
        nodes = all_nodes(edge)
        hypernodes = Base.getindex.(projection, nodes)
        @assert length(hypernodes) >= 2
        hyperedge = Graphs.add_edge!(hypergraph, hypernodes...)
        projection[hyperedge] = edge
        projection[edge] = hyperedge
    end
    return projection
end
@deprecate gethypergraph hyper_projection
@deprecate hyper_graph hyper_projection

struct CliqueGraphProjectionType <: AbstractProjectionType end

"""
    clique_projection(graph::OptiGraph)

Retrieve a standard graph representation of `graph`. The projection contains a standard
`Graphs.Graph` and a mapping between its elements and the given optigraph. This projection
works by creating an edge for each pair of nodes in each hyperedge.
"""
function clique_projection(graph::OptiGraph)
    clique_graph = Graphs.Graph()
    projection = GraphProjection(graph, clique_graph, CliqueGraphProjectionType())
    for optinode in all_nodes(graph)
        Graphs.add_vertex!(clique_graph)
        vertex = nv(clique_graph)
        projection[vertex] = optinode
        projection[optinode] = vertex
    end
    for edge in all_edges(graph)
        nodes = edge.nodes
        edge_vertices = [projection[optinode] for optinode in nodes]
        for i in 1:length(edge_vertices)
            vertex_from = edge_vertices[i]
            other_vertices = edge_vertices[(i + 1):end]
            for j in 1:length(other_vertices)
                vertex_to = other_vertices[j]
                inserted = Graphs.add_edge!(clique_graph, vertex_from, vertex_to)
            end
        end
    end
    return projection
end
@deprecate getcliquegraph clique_projection
@deprecate clique_graph clique_projection

struct EdgeGraphProjectionType <: AbstractProjectionType end

"""
    edge_clique_projection(graph::OptiGraph)

Retrieve the edge-graph representation of optigraph `graph`. This is sometimes called the 
line graph of a hypergraph.
"""
function edge_clique_projection(graph::OptiGraph)
    edge_graph = Graphs.Graph()
    projection = GraphProjection(graph, edge_graph, EdgeGraphProjectionType())
    for optiedge in all_edges(graph)
        Graphs.add_vertex!(edge_graph)
        vertex = nv(edge_graph)
        projection[vertex] = optiedge
        projection[optiedge] = vertex
    end
    edge_array = all_edges(graph)
    n_edges = length(edge_array)
    for i in 1:(n_edges - 1)
        for j in (i + 1):n_edges
            e1 = edge_array[i]
            e2 = edge_array[j]
            if !isempty(intersect(e1.nodes, e2.nodes))
                Graphs.add_edge!(edge_graph, projection[e1], projection[e2])
            end
        end
    end
    return projection
end
@deprecate edge_graph edge_clique_projection

struct EdgeHyperGraphProjectionType <: AbstractProjectionType end

"""
    edge_hyper_projection(graph::OptiGraph)

Retrieve an edge-hypergraph representation of the optigraph `graph`. This is sometimes 
called  the dual-hypergraph representation of a hypergraph.
"""
function edge_hyper_projection(graph::OptiGraph)
    # create a primal hypergraph first. we need to do this to get the node --> edge mapping
    primal_map = hyper_projection(graph)

    # build the edge hypergraph
    hypergraph = GOI.HyperGraph()
    projection = GraphProjection(graph, hypergraph, EdgeHyperGraphProjectionType())
    for edge in all_edges(graph)
        hypernode = Graphs.add_vertex!(hypergraph)
        projection[hypernode] = edge
        projection[edge] = hypernode
    end
    for node in all_nodes(graph)
        hyperedges = incident_edges(primal_map, node)
        dual_nodes = Base.getindex.(projection, hyperedges)
        # NOTE: a hypergraph may not always have a valid edge projection; we only
        # add the hyperedge if it is possible.
        if length(dual_nodes) >= 2
            #@assert length(dual_nodes) >= 2
            hyperedge = Graphs.add_edge!(hypergraph, dual_nodes...)
            projection[hyperedge] = node
            projection[node] = hyperedge
        end
    end
    return projection
end
@deprecate edge_hyper_graph edge_hyper_projection

struct BipartiteGraphProjectionType <: AbstractProjectionType end

"""
    bipartite_graph(graph::OptiGraph)

Create a bipartite graph representation from `graph`.  The bipartite graph contains two 
sets of vertices corresponding to optinodes and optiedges respectively.
"""
function bipartite_projection(graph::OptiGraph)
    bipartite_graph = GOI.BipartiteGraph()
    projection = GraphProjection(graph, bipartite_graph, BipartiteGraphProjectionType())
    for optinode in all_nodes(graph)
        Graphs.add_vertex!(bipartite_graph; bipartite=1)
        node_vertex = nv(bipartite_graph)
        projection[node_vertex] = optinode
        projection[optinode] = node_vertex
    end
    for edge in all_edges(graph)
        Graphs.add_vertex!(bipartite_graph; bipartite=2)
        edge_vertex = nv(bipartite_graph)
        projection[edge] = edge_vertex
        projection[edge_vertex] = edge
        nodes = edge.nodes
        edge_vertices = [projection[optinode] for optinode in nodes]
        for node_vertex in edge_vertices
            Graphs.add_edge!(bipartite_graph, edge_vertex, node_vertex)
        end
    end
    return projection
end
@deprecate bipartite_graph bipartite_projection

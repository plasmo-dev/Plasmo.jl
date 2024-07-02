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

Retrieve a hypergraph representation of the optigraph `graph`. Returns a [`HyperGraph`](@ref) object, as well as a dictionary
that maps hypernodes and hyperedges to the original optinodes and optiedges.
"""
function hyper_projection(optigraph::OptiGraph)
    hypergraph = GOI.HyperGraph()
    projection = GraphProjection(optigraph, hypergraph, HyperGraphProjectionType())
    for node in all_nodes(optigraph)
        hypernode = Graphs.add_vertex!(hypergraph)
        projection[hypernode] = node
        projection[node] = hypernode
    end
    for edge in all_edges(optigraph)
        nodes = all_nodes(edge)
        hypernodes = Base.getindex.(projection, nodes)
        @assert length(hypernodes) >= 2
        hyperedge = Graphs.add_edge!(hypergraph, hypernodes...)
        projection[hyperedge] = edge
        projection[edge] = hyperedge
    end
    return projection
end
@deprecate gethypergraph build_hyper_graph
@deprecate hyper_graph build_hyper_graph

struct CliqueGraphProjectionType <: AbstractProjectionType end

"""
    build_clique_graph(graph::OptiGraph)

Retrieve a standard graph representation of the optigraph `graph`. Returns a `LightGraphs.Graph` object, as well as a dictionary
that maps vertices and edges to the optinodes and optiedges.
"""
function clique_projection(optigraph::OptiGraph)
    graph = Graphs.Graph()
    projection = GraphProjection(optigraph, graph, CliqueGraphProjectionType())
    for optinode in all_nodes(optigraph)
        Graphs.add_vertex!(graph)
        vertex = nv(graph)
        projection[vertex] = optinode
        projection[optinode] = vertex
    end
    for edge in all_edges(optigraph)
        nodes = edge.nodes
        edge_vertices = [projection[optinode] for optinode in nodes]
        for i in 1:length(edge_vertices)
            vertex_from = edge_vertices[i]
            other_vertices = edge_vertices[(i + 1):end]
            for j in 1:length(other_vertices)
                vertex_to = other_vertices[j]
                inserted = Graphs.add_edge!(graph, vertex_from, vertex_to)
            end
        end
    end
    return projection
end
@deprecate getcliquegraph build_clique_graph
@deprecate clique_graph build_clique_graph

struct EdgeGraphProjectionType <: AbstractProjectionType end

"""
    edge_graph(optigraph::OptiGraph)

Retrieve the edge-graph representation of `optigraph`. This is sometimes called the line graph of a hypergraph.
Returns a `GraphProjection`.
"""
function edge_clique_projection(optigraph::OptiGraph)
    graph = Graphs.Graph()
    projection = GraphProjection(optigraph, graph, EdgeGraphProjectionType())
    for optiedge in all_edges(optigraph)
        Graphs.add_vertex!(graph)
        vertex = nv(graph)
        projection[vertex] = optiedge
        projection[optiedge] = vertex
    end
    edge_array = all_edges(optigraph)
    n_edges = length(edge_array)
    for i in 1:(n_edges - 1)
        for j in (i + 1):n_edges
            e1 = edge_array[i]
            e2 = edge_array[j]
            if !isempty(intersect(e1.nodes, e2.nodes))
                Graphs.add_edge!(graph, projection[e1], projection[e2])
            end
        end
    end
    return projection
end
@deprecate edge_graph build_edge_graph

struct EdgeHyperGraphProjectionType <: AbstractProjectionType end

"""
    edge_hyper_graph(graph::OptiGraph)

Retrieve an edge-hypergraph representation of the optigraph `graph`. Returns a [`GraphProjection`](@ref) object, as well as a dictionary
that maps hypernodes and hyperedges to the original optinodes and optiedges. This is also called the dual-hypergraph representation of a hypergraph.
"""
function edge_hyper_projection(optigraph::OptiGraph)
    # create a primal hypergraph first. we need to do this to get the node --> edge mapping
    primal_map = hyper_projection(optigraph)

    # build the edge hypergraph
    hypergraph = GOI.HyperGraph()
    projection = GraphProjection(optigraph, hypergraph, EdgeHyperGraphProjectionType())
    for edge in all_edges(optigraph)
        hypernode = Graphs.add_vertex!(hypergraph)
        projection[hypernode] = edge
        projection[edge] = hypernode
    end
    for node in all_nodes(optigraph)
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
@deprecate edge_hyper_graph build_edge_hypergraph

struct BipartiteGraphProjectionType <: AbstractProjectionType end

"""
    bipartite_graph(optigraph::OptiGraph)

Create a bipartite graph representation from `optigraph`.  
The bipartite graph contains two sets of vertices corresponding to optinodes and optiedges respectively.
"""
function bipartite_projection(optigraph::OptiGraph)
    graph = GOI.BipartiteGraph()
    projection = GraphProjection(optigraph, graph, BipartiteGraphProjectionType())
    for optinode in all_nodes(optigraph)
        Graphs.add_vertex!(graph; bipartite=1)
        node_vertex = nv(graph)
        projection[node_vertex] = optinode
        projection[optinode] = node_vertex
    end
    for edge in all_edges(optigraph)
        Graphs.add_vertex!(graph; bipartite=2)
        edge_vertex = nv(graph)
        projection[edge] = edge_vertex
        projection[edge_vertex] = edge
        nodes = edge.nodes
        edge_vertices = [projection[optinode] for optinode in nodes]
        for node_vertex in edge_vertices
            Graphs.add_edge!(graph, edge_vertex, node_vertex)
        end
    end
    return projection
end
@deprecate bipartite_graph build_bipartite_graph

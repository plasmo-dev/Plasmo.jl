#Checkout how SimpleGraph works to implement this Interface
#NOTE This will be a super simple hypergraph object.
#I will have functions that turn this generalized hypergraph into different kinds of bipartite graphs for which algorithms could work on
#IDEA Model graph uses the generic hyper edge for all edges.  It is possible to convert a model graph into different kinds of LightGraph graphs to do different types of analyses.
import Base.==

abstract type AbstractHyperGraph <: LightGraphs.AbstractGraph{Int64} end
abstract type AbstractHyperEdge <: LightGraphs.AbstractEdge{Int64} end


import LightGraphs:AbstractGraph
# LightGraphs.AbstractGraph
mutable struct HyperGraph <: AbstractHyperGraph
    vertices::Vector{Int}
    edges::Vector{AbstractHyperEdge}
    node_map::Dict{Int,Vector{AbstractHyperEdge}}  #map nodes to hyper edges
end
HyperGraph(n::Integer = 0) = HyperGraph(Int[],AbstractHyperEdge[],Dict{Int,Vector{AbstractHyperEdge}}())

#LightGraphs.AbstractEdge
#NOTE Use an inner constructor to enforce ordering
struct HyperEdge <: AbstractHyperEdge
    vertices::Tuple  #vertices the edge connects.  Ordered by vertex number
end
HyperEdge(t::Vector{Int64}) = HyperEdge(tuple(sort(t)...))
HyperEdge(t::Int...) = HyperEdge(tuple(sort(collect(t))...))
#convert a simple edge to a hyperedge
HyperEdge(edge::SimpleEdge) = HyperEdge(tuple(sort([src(edge),dst(edge)])...))
HyperEdge(edge::HyperEdge) = edge

show(io::IO, e::HyperEdge) = print(io, "Hyper Edge $(e.vertices)")

#
# Base.broadcast(::typeof(==),h1::HyperEdge,h2::HyperEdge) = sort(unique(h1.vertices)) ==  sort(unique(h2.vertices))
# Base.==(::HyperEdge,::HyperEdge) = sort(unique(h1.vertices)) ==  sort(unique(h2.vertices))
==(h1::HyperEdge,h2::HyperEdge) = sort(unique(h1.vertices)) ==  sort(unique(h2.vertices))
# function Base.==(h1::HyperEdge,h2::HyperEdge)
#     val = sort(unique(h1.vertices)) ==  sort(unique(h2.vertices))
#     return val
# end

function LightGraphs.add_vertex!(g::HyperGraph)
    (nv(g) + one(Int) <= nv(g)) && return false       # test for overflow
    v = length(g.vertices)+1
    push!(g.vertices,v)
    g.node_map[v] = AbstractHyperEdge[]
    return true
end

Base.reverse(e::HyperEdge) = nothing

# LightGraphs.add_edge!
function LightGraphs.add_edge!(g::HyperGraph, e::HyperEdge)
    #all(e.vertices in vertices(g)) || return false
    (all(v->v in vertices(g), e.vertices) && !(e in g.edges)) || return false  #NOTE This might not be working

    inserted = begin
        for v in e.vertices
            #NOTE Push to array, don't override
            push!(g.node_map[v], e)
        end
        true
    end
    if inserted
        push!(g.edges,e)
    end
    return inserted
end

function LightGraphs.add_edge!(g::HyperGraph,vertices::Int...)
    hedge = HyperEdge(vertices)
    inserted = add_edge!(g,hedge)
    return inserted
end

function LightGraphs.add_edge!(g::HyperGraph,edge::SimpleEdge)
    hedge = HyperEdge(src(edge),dst(edge))
    inserted = add_edge!(g,hedge)
    return inserted
end

# LightGraphs.src
LightGraphs.src(g::HyperGraph) = throw(error("src not defined for HyperGraphs"))

# LightGraphs.dst
LightGraphs.dst(g::HyperGraph) = throw(error("dst not defined for HyperGraphs"))

# #LightGraphs.edges
LightGraphs.edges(g::HyperGraph) = g.edges #HyperEdgeIter(g)

# LightGraphs.edgetype
LightGraphs.edgetype(g::HyperGraph) = HyperEdge

# LightGraphs.has_edge
LightGraphs.has_edge(g::HyperGraph,e::HyperEdge) = e in g.edges

# LightGraphs.has_vertex
LightGraphs.has_vertex(g::HyperGraph, v::Integer) = v in vertices(g)

# LightGraphs.is_directed
LightGraphs.is_directed(g::HyperGraph) = false

LightGraphs.is_directed(::Type{HyperGraph}) = false

# LightGraphs.ne
LightGraphs.ne(g::HyperGraph) = length(g.edges)
# LightGraphs.nv
LightGraphs.nv(g::HyperGraph) = length(g.vertices)

# LightGraphs.inneighbors
#LightGraphs.inneighbors(g::HyperGraph, v::Integer) = nothing

# LightGraphs.outneighbors
#LightGraphs.outneighbors(g::HyperGraph, v::Integer) = nothing

# LightGraphs.rem_edge!
#TODO This shouldn't be too bad
LightGraphs.rem_edge!(g::HyperGraph,e::HyperEdge) = throw(error("Edge removal not supported on hypergraphs"))
# function rem_edge!(g::SimpleGraph, e::SimpleGraphEdge)
#     i = searchsorted(g.fadjlist[src(e)], dst(e))
#     isempty(i) && return false   # edge not in graph
#     j = first(i)
#     deleteat!(g.fadjlist[src(e)], j)
#     if src(e) != dst(e)     # not a self loop
#         j = searchsortedfirst(g.fadjlist[dst(e)], src(e))
#         deleteat!(g.fadjlist[dst(e)], j)
#     end
#     g.ne -= 1
#     return true # edge successfully removed
# end

# LightGraphs.rem_vertex!
#TODO Delete any associated edges with the vertex
LightGraphs.rem_vertex!(g::HyperGraph) = throw(error("Vertex removal not supported on hypergraphs"))

# LightGraphs.vertices
LightGraphs.vertices(g::HyperGraph) = g.vertices

#NOTE Inefficient neighbors implementation
function LightGraphs.all_neighbors(g::HyperGraph,v::Int)
    hyperedges = g.node_map[v]
    neighbors = []
    for edge in hyperedges
        #append!(neighbors,edge.vertices[1:end .!= v])  #NOTE This doesn't seem to work
        append!(neighbors,[vert for vert in edge.vertices if vert != v])
    end
    return unique(neighbors)
end

LightGraphs.degree(g::HyperGraph,v::Int) = length(all_neighbors(g,v))

#neighbors(basegraph::BasePlasmoGraph,node::BasePlasmoNode) = [getnode(basegraph,node_index) for node_index in LightGraphs.all_neighbors(getlightgraph(basegraph),getindex(basegraph,node))]

#neighbors

#getsupportingnodes


# LightGraphs.AbstractEdgeIter
# struct HyperEdgeIter <: LightGraphs.AbstractEdgeIter
#     g::HyperGraph
#     edges::Vector{HyperEdge}
# end
#
# start(eit::HyperEdgeIter) = eit.edges[1]
#
# done(eit::HyperEdgeIter) = eit.edges[end]
#
# length(eit::HyperEdgeIter) = ne(eit.g)
#
# next(eit::HyperEdgeIter) = edge_next(eit.g, state)

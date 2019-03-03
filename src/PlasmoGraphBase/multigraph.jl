import Base.==

abstract type AbstractMultiGraph <: LightGraphs.AbstractGraph{Int64} end
abstract type AbstractMultiEdge <: LightGraphs.AbstractEdge{Int64} end

#A simple multi-graph implementation
mutable struct MultiGraph <: AbstractMultiGraph
    vertices::Vector{Int}
    edges::Vector{AbstractMultiEdge}
    node_map_in::Dict{Int,Vector{AbstractMultiEdge}}  #map nodes to hyper edges
    node_map_out::Dict{Int,Vector{AbstractMultiEdge}}
    edge_map::Dict{LightGraphs.SimpleEdge,Vector{AbstractMultiEdge}}
end

mutable struct MultiEdge <: AbstractMultiEdge
    src::Int
    dst::Int
    id::Int   #id corresponds to which edge from src to dst
end
MultiEdge(p::Pair) = MultiEdge(p.first,p.second,0)

#convert a simple edge to a hyperedge
MultiEdge(edge::SimpleEdge) = MultiEdge(src(edge),dst(edge),0)
MultiEdge(edge::MultiEdge) = edge
MultiEdge(src::Int,dst::Int) = MultiEdge(src,dst,0)

show(io::IO, e::MultiEdge) = print(io, "Multi Edge $(e.src),$(e.dst)")

==(e1::MultiEdge,e2::MultiEdge) = e1.src == e2.src && e1.dst == e2.dst && e1.id == e2.id

#MultiGraph Constructor
MultiGraph() = MultiGraph(Int[],MultiEdge[],Dict{Int,Vector{MultiEdge}}(),Dict{Int,Vector{MultiEdge}}(),Dict{LightGraphs.SimpleEdge,MultiEdge}())

function LightGraphs.add_vertex!(g::MultiGraph)
    (nv(g) + one(Int) <= nv(g)) && return false       # test for overflow
    v = length(g.vertices)+1
    push!(g.vertices,v)
    g.node_map_in[v] = AbstractMultiEdge[]
    g.node_map_out[v] = AbstractMultiEdge[]
    return true
end

Base.reverse(e::MultiEdge) = nothing

# LightGraphs.add_edge!
function LightGraphs.add_edge!(g::MultiGraph, e::MultiEdge)
    (e.src in vertices(g) && e.dst in vertices(g)) || return false

    inserted = begin
        push!(g.node_map_in[e.dst],e)
        push!(g.node_map_out[e.src],e)

        if haskey(g.edge_map,LightGraphs.SimpleEdge(e.src,e.dst))
            push!(g.edge_map[LightGraphs.SimpleEdge(e.src,e.dst)],e)  #map a simple edge (src,dst) to every multi-edge corresponding to src and dst
        else
            g.edge_map[LightGraphs.SimpleEdge(e.src,e.dst)] = [e]
        end

        e.id = length(g.edge_map[LightGraphs.SimpleEdge(e.src,e.dst)])  #set multi-edge id
        true
    end
    if inserted
        push!(g.edges,e)
    end
    return inserted
end

function LightGraphs.add_edge!(g::MultiGraph,src::Int,dst::Int)
    medge = MultiEdge(src,dst)
    inserted = add_edge!(g,medge)
    return inserted
end

function LightGraphs.add_edge!(g::MultiGraph,edge::SimpleEdge)
    medge = MultiEdge(edge)
    inserted = add_edge!(g,medge)
    return inserted
end

# LightGraphs.src
LightGraphs.src(g::MultiGraph,e::MultiEdge) = e.src

# LightGraphs.dst
LightGraphs.dst(g::MultiGraph,e::MultiEdge) = e.dst

# #LightGraphs.edges
LightGraphs.edges(g::MultiGraph) = g.edges

# LightGraphs.edgetype
LightGraphs.edgetype(g::MultiGraph) = MultiEdge

# LightGraphs.has_edge
LightGraphs.has_edge(g::MultiGraph,e::MultiEdge) = e in g.edges

# LightGraphs.has_vertex
LightGraphs.has_vertex(g::MultiGraph, v::Integer) = v in vertices(g)

# LightGraphs.is_directed
LightGraphs.is_directed(g::MultiGraph) = true

LightGraphs.is_directed(::Type{MultiGraph}) = true

# LightGraphs.ne
LightGraphs.ne(g::MultiGraph) = length(g.edges)
# LightGraphs.nv
LightGraphs.nv(g::MultiGraph) = length(g.vertices)

LightGraphs.vertices(g::MultiGraph) = g.vertices

#NOTE Inefficient neighbors implementation
# function LightGraphs.all_neighbors(g::MultiGraph,v::Int)
#     multiedges = g.node_map_in[v]
#     neighbors = []
#     for edge in hyperedges
#         #append!(neighbors,edge.vertices[1:end .!= v])  #NOTE This doesn't seem to work
#         append!(neighbors,[vert for vert in edge.vertices if vert != v])
#     end
#     return unique(neighbors)
# end

#LightGraphs.degree(g::HyperGraph,v::Int) = length(all_neighbors(g,v))

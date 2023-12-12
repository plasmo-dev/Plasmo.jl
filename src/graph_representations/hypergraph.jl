abstract type AbstractHyperGraph <: LightGraphs.AbstractGraph{Int64} end
abstract type AbstractHyperEdge <: LightGraphs.AbstractEdge{Int64} end

const HyperNode = Int64
struct HyperEdge <: AbstractHyperEdge
    vertices::Set{HyperNode}
end
HyperEdge(t::Vector{HyperNode}) = HyperEdge(Set(t))
HyperEdge(t::HyperNode...) = HyperEdge(Set(collect(t)))

"""
    HyperGraph

A simple hypergraph type.  Contains attributes for vertices and hyperedges.
"""
mutable struct HyperGraph <: AbstractHyperGraph
    vertices::Vector{HyperNode}
    hyperedge_map::OrderedDict{Int64,HyperEdge}  #look up hyperedges by index in the hypergraph
    hyperedges::OrderedDict{Set,Int64} #{Set,HyperEdge}           #look up hyperedge index using hypernodes.
    node_map::Dict{HyperNode,Vector{HyperEdge}}  #map hypernodes to hyperedges they are incident to
end
function HyperGraph()
    return HyperGraph(
        HyperNode[],
        OrderedDict{Int64,HyperEdge}(),
        OrderedDict{Set,HyperEdge}(),
        Dict{HyperNode,Vector{HyperEdge}}(),
    )
end

#HyperNode
function LightGraphs.add_vertex!(hypergraph::HyperGraph)
    (nv(hypergraph) + one(Int) <= nv(hypergraph)) && return false       # test for overflow
    v = length(hypergraph.vertices) + 1
    hypernode = v
    push!(hypergraph.vertices, hypernode)
    hypergraph.node_map[hypernode] = HyperEdge[]
    return hypernode
end

add_node!(hypergraph::HyperGraph) = LightGraphs.add_vertex!(hypergraph)
getnode(hypergraph::HyperGraph, index::Int64) = hypergraph.vertices[index]
Base.getindex(hypergraph::HyperGraph, node::HyperNode) = node
getnodes(hypergraph::HyperGraph) = hypergraph.vertices

#HyperEdge
Base.reverse(e::HyperEdge) = error("A hyperedge does not support reverse()")
==(h1::HyperEdge, h2::HyperEdge) = collect(h1.vertices) == collect(h2.vertices)
function LightGraphs.add_edge!(graph::HyperGraph, vertices::HyperNode...)
    return add_hyperedge!(graph, vertices...)
end
gethypernodes(edge::HyperEdge) = collect(edge.vertices)

function add_hyperedge!(hypergraph::HyperGraph, hypernodes::HyperNode...)
    @assert length(hypernodes) > 1
    hypernodes = Set(collect(hypernodes))
    if has_edge(hypergraph, hypernodes)
        return gethyperedge(hypernodes)
        #return hypergraph.hyperedges[hypernodes]
    else
        index = ne(hypergraph) + 1
        hyperedge = HyperEdge(hypernodes...)
        for hypernode in hypernodes
            push!(hypergraph.node_map[hypernode], hyperedge)
        end
        hypergraph.hyperedges[hypernodes] = index
        hypergraph.hyperedge_map[index] = hyperedge
        return hyperedge
    end
end
#Getters
function gethyperedge(hypergraph::HyperGraph, edge_index::Int64)
    return hypergraph.hyperedge_map[edge_index]
end
function gethyperedge(hypergraph::HyperGraph, hypernodes::Set)
    edge_index = hypergraph.hyperedges[hypernodes]
    return hypergraph.hyperedge_map[edge_index]
end
gethyperedges(hypergraph::HyperGraph) = values(hypergraph.hyperedges)
getedges(hypergraph::HyperGraph) = gethyperedges(hypergraph)
LightGraphs.vertices(hyperedge::HyperEdge) = collect(hyperedge.vertices)

function Base.getindex(hypergraph::HyperGraph, edge::HyperEdge)
    hypernodes = edge.vertices
    return hypergraph.hyperedges[hypernodes]
end

#LightGraphs Interface
LightGraphs.edges(graph::HyperGraph) = graph.hyperedges
LightGraphs.edgetype(graph::HyperGraph) = HyperEdge
function LightGraphs.has_edge(graph::HyperGraph, edge::HyperEdge)
    return edge in values(graph.hyperedge_map)
end
function LightGraphs.has_edge(graph::HyperGraph, hypernodes::Set{HyperNode})
    return haskey(graph.hyperedges, hypernodes)
end
LightGraphs.has_vertex(graph::HyperGraph, v::Integer) = v in vertices(graph)
LightGraphs.is_directed(graph::HyperGraph) = false
LightGraphs.is_directed(::Type{HyperGraph}) = false
LightGraphs.ne(graph::HyperGraph) = length(graph.hyperedge_map)
LightGraphs.nv(graph::HyperGraph) = length(graph.vertices)
LightGraphs.vertices(graph::HyperGraph) = graph.vertices
LightGraphs.degree(g::HyperGraph, v::Int) = length(all_neighbors(g, v))

function LightGraphs.all_neighbors(g::HyperGraph, node::HyperNode)
    hyperedges = g.node_map[node]  #incident hyperedges to the hypernode
    neighbors = HyperNode[]
    for edge in hyperedges
        append!(neighbors, [vert for vert in edge.vertices if vert != node])
    end
    return unique(neighbors)
end

"""
    LightGraphs.incidence_matrix(hypergraph::HyperGraph)

Obtain the incidence matrix representation of `hypergraph`.  Rows correspond to vertices. Columns correspond to hyperedges.
Returns a sparse matrix.
"""
function LightGraphs.incidence_matrix(hypergraph::HyperGraph)
    I = []
    J = []
    for (edge_index, hyperedge) in hypergraph.hyperedge_map
        node_indices = sort(collect(hyperedge.vertices))
        for node_index in node_indices
            push!(I, node_index)
            push!(J, edge_index)
        end
    end
    V = Int.(ones(length(I)))
    m = length(hypergraph.vertices)
    n = length(hypergraph.hyperedge_map)
    return SparseArrays.sparse(I, J, V, m, n)
end

"""
    LightGraphs.adjacency_matrix(hypergraph::HyperGraph)

Obtain the adjacency matrix from `hypergraph.` Returns a sparse matrix.
"""
function LightGraphs.adjacency_matrix(hypergraph::HyperGraph)
    I = []
    J = []
    for vertex in vertices(hypergraph)
        for neighbor in LightGraphs.all_neighbors(hypergraph, vertex)
            push!(I, vertex)
            push!(J, neighbor)
        end
    end
    V = Int.(ones(length(I)))
    return SparseArrays.sparse(I, J, V)
end

SparseArrays.sparse(hypergraph::HyperGraph) = LightGraphs.incidence_matrix(hypergraph)

#HYPERGRAPH SPECIFIC FUNCTIONS
"""
    incident_edges(hypergraph::HyperGraph,hypernode::HyperNode)

Identify the incident hyperedges to a `HyperNode`.
"""
function incident_edges(g::HyperGraph, node::HyperNode)
    hyperedges = HyperEdge[]
    for hyperedge in g.node_map[node]
        push!(hyperedges, hyperedge)
    end
    return hyperedges
end

"""
    induced_edges(hypergraph::HyperGraph,hypernodes::Vector{HyperNode})

Identify the induced hyperedges to a vector of `HyperNode`s.

NOTE: This currently does not support hypergraphs with unconnected nodes
"""
function induced_edges(hypergraph::HyperGraph, hypernodes::Vector{HyperNode})
    external_nodes = setdiff(hypergraph.vertices, hypernodes) #nodes in hypergraph that aren't in hypernodes
    #Create partition matrix
    I = []
    J = []
    for hypernode in hypernodes
        j = getindex(hypergraph, hypernode)
        push!(I, 1)
        push!(J, j)
    end
    for hypernode in external_nodes
        j = getindex(hypergraph, hypernode)
        push!(I, 2)
        push!(J, j)
    end

    V = Int.(ones(length(J)))
    G = sparse(I, J, V)  #Node partition matrix
    A = sparse(hypergraph)
    C = G * A  #Edge partitions

    #FIND THE SHARED EDGES, Get indices of shared edges
    sum_vector = sum(C; dims=1)
    max_vector = maximum(C; dims=1)
    cross_vector = sum_vector - max_vector

    #nonzero indices of the cross vector.  these are edges that cross partitions.
    indices = findall(cross_vector .!= 0)
    indices = [indices[i].I[2] for i in 1:length(indices)]

    inds = findall(C[1, :] .!= 0)
    new_inds = filter(x -> !(x in indices), inds) #these are edge indices
    induced_edges = HyperEdge[gethyperedge(hypergraph, new_ind) for new_ind in new_inds]

    return induced_edges
end

"""
    incident_edges(hypergraph::HyperGraph,hypernodes::Vector{HyperNode})

Identify the incident hyperedges to a vector of `HyperNode`s.
"""
function incident_edges(hypergraph::HyperGraph, hypernodes::Vector{HyperNode})
    external_nodes = setdiff(hypergraph.vertices, hypernodes) #nodes in hypergraph that aren't in hypernodes
    #Create partition matrix
    I = []
    J = []
    for hypernode in hypernodes
        #j = getindex(hypergraph,hypernode)
        j = hypernode
        push!(I, 1)
        push!(J, j)
    end
    for hypernode in external_nodes
        #j = getindex(hypergraph,hypernode)
        j = hypernode
        push!(I, 2)
        push!(J, j)
    end

    V = Int.(ones(length(J)))
    G = sparse(I, J, V)  #Node partition matrix
    A = sparse(hypergraph)
    C = G * A  #Edge partitions

    #FIND THE SHARED EDGES, Get indices of shared edges
    sum_vector = sum(C; dims=1)
    max_vector = maximum(C; dims=1)
    cross_vector = sum_vector - max_vector
    indices = findall(cross_vector .!= 0)                   #nonzero indices of the cross vector.  These are edges that cross partitions.
    indices = [indices[i].I[2] for i in 1:length(indices)]

    incident_edges = HyperEdge[gethyperedge(hypergraph, index) for index in indices]

    return incident_edges
end

"""
    identify_edges(hypergraph::HyperGraph,partitions::Vector{Vector{HyperNode}})

Identify both induced partition edges and cut edges given a partition of `HyperNode` vectors.
"""
function identify_edges(hypergraph::HyperGraph, partitions::Vector{Vector{HyperNode}})
    nparts = length(partitions)

    #Create partition matrix
    I = []
    J = []
    for i in 1:nparts
        for hypernode in partitions[i]
            j = hypernode
            push!(I, i)
            push!(J, j)
        end
    end

    V = Int.(ones(length(J)))
    G = sparse(I, J, V)  #Node partition matrix
    #A = sparse(hypergraph)
    A = incidence_matrix(hypergraph)
    C = G * A  #Edge partitions

    #FIND THE SHARED EDGES, Get indices of shared edges
    sum_vector = sum(C; dims=1)
    max_vector = maximum(C; dims=1)
    cross_vector = sum_vector - max_vector
    indices = findall(cross_vector .!= 0)                   #nonzero indices of the cross vector.  These are edges that cross partitions.
    indices = [indices[i].I[2] for i in 1:length(indices)]   #convert to Integers

    shared_edges = HyperEdge[]
    for index in indices
        push!(shared_edges, gethyperedge(hypergraph, index))
    end

    #GET INDUCED PARTITION EDGES (I.E GET THE EDGES LOCAL TO EACH PARTITION)
    partition_edges = Vector[Vector{HyperEdge}() for _ in 1:nparts]
    for i in 1:nparts
        inds = findall(C[i, :] .!= 0)
        new_inds = filter(x -> !(x in indices), inds) #these are edge indices
        for new_ind in new_inds
            push!(partition_edges[i], gethyperedge(hypergraph, new_ind))
        end
    end

    return partition_edges, shared_edges
end

"""
    identify_nodes(hypergraph::HyperGraph,partitions::Vector{Vector{HyperEdge}})

Identify both induced partition nodes and cut nodes given a partition of `HyperEdge` vectors.
"""
function identify_nodes(hypergraph::HyperGraph, partitions::Vector{Vector{HyperEdge}})
    nparts = length(partitions)

    #Create partition matrix
    I = []
    J = []
    for i in 1:nparts
        for hyperedge in partitions[i]
            j = getindex(hypergraph, hyperedge)
            push!(I, i)
            push!(J, j)
        end
    end

    V = Int.(ones(length(J)))
    G = sparse(I, J, V)  #Edge partition matrix
    A = incidence_matrix(hypergraph)
    C = A * G'  #Node Partitions

    #FIND THE SHARED NODES, Get indices of shared nodes
    sum_vector = sum(C; dims=2)
    max_vector = maximum(C; dims=2)
    cross_vector = sum_vector - max_vector
    indices = findall(cross_vector .!= 0)                   #nonzero indices of the cross vector.  These are edges that cross partitions.
    indices = [indices[i].I[1] for i in 1:length(indices)]   #convert to Integers

    shared_nodes = HyperNode[]
    for index in indices
        push!(shared_nodes, getnode(hypergraph, index))
    end

    #GET INDUCED PARTITION NODES (I.E GET THE NODES LOCAL TO EACH PARTITION)
    partition_nodes = Vector[Vector{HyperNode}() for _ in 1:nparts]
    for i in 1:nparts
        inds = findall(C[:, i] .!= 0)
        new_inds = filter(x -> !(x in indices), inds) #these are edge indices
        for new_ind in new_inds
            push!(partition_nodes[i], getnode(hypergraph, new_ind))
        end
    end

    return partition_nodes, shared_nodes
end

induced_elements(hypergraph::HyperGraph, partitions::Vector{Vector{HyperNode}}) = partitions

"""
    neighborhood(g::HyperGraph,nodes::Vector{OptiNode},distance::Int64)

Retrieve the neighborhood within `distance` of `nodes`.  Returns a vector of the original vertices and added vertices
"""
function neighborhood(g::HyperGraph, nodes::Vector{HyperNode}, distance::Int64)
    V = collect(nodes)
    nbr = copy(V)
    newnbr = copy(V) #neighbors to check
    addnbr = Int64[]
    for k in 1:distance
        for i in newnbr
            append!(addnbr, all_neighbors(g, i)) #NOTE: union! is slow
        end
        newnbr = setdiff(addnbr, nbr)
    end
    nbr = unique([nbr; addnbr])
    return nbr
end

function expand(g::HyperGraph, nodes::Vector{HyperNode}, distance::Int64)
    new_nodes = neighborhood(g, nodes, distance)
    new_edges = induced_edges(g, new_nodes)
    return new_nodes, new_edges
end

#TODO
function LightGraphs.rem_edge!(g::HyperGraph, e::HyperEdge)
    throw(error("Edge removal not yet supported on hypergraphs"))
end
function LightGraphs.rem_vertex!(g::HyperGraph)
    throw(error("Vertex removal not yet supported on hypergraphs"))
end

####################################
#Print Functions
####################################
function string(graph::HyperGraph)
    return "Hypergraph: " * "($(nv(graph)) , $(ne(graph)))"
end
print(io::IO, graph::HyperGraph) = print(io, string(graph))
show(io::IO, graph::HyperGraph) = print(io, graph)

function string(edge::HyperEdge)
    return "HyperEdge: " * "$(collect(edge.vertices))"
end
print(io::IO, edge::HyperEdge) = print(io, string(edge))
show(io::IO, edge::HyperEdge) = print(io, edge)

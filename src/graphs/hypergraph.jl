abstract type AbstractHyperGraph <: LightGraphs.AbstractGraph{Int64} end
abstract type AbstractHyperEdge <: LightGraphs.AbstractEdge{Int64} end

const HyperNode = Int64
struct HyperEdge <: AbstractHyperEdge
    vertices::Set{HyperNode}
end
HyperEdge(t::Vector{HyperNode}) = HyperEdge(Set(t))
HyperEdge(t::HyperNode...) = HyperEdge(Set(collect(t)))

"""
    Hypergraph

A simple hypergraph type.  Contains attributes for vertices and hyperedges.
"""
mutable struct HyperGraph <: AbstractHyperGraph
    vertices::Vector{HyperNode}
    hyperedge_map::OrderedDict{Int64,HyperEdge}  #look up hyperedges by index in the hypergraph
    hyperedges::OrderedDict{Set,HyperEdge}       #look up hyperedges using hypernodes.  These are LOCAL to the hypergraph
    node_map::Dict{HyperNode,Vector{HyperEdge}}  #map hypernodes to hyperedges they are incident to
end
HyperGraph() = HyperGraph(HyperNode[],OrderedDict{Int64,HyperEdge}(),OrderedDict{Set,HyperEdge}(),Dict{HyperNode,Vector{HyperEdge}}())

#HyperNode
function LightGraphs.add_vertex!(hypergraph::HyperGraph)
    (nv(hypergraph) + one(Int) <= nv(hypergraph)) && return false       # test for overflow
    v = length(hypergraph.vertices)+1
    hypernode = v
    push!(hypergraph.vertices,hypernode)
    hypergraph.node_map[hypernode] = HyperEdge[]
    return hypernode
end

add_node!(hypergraph::HyperGraph) = LightGraphs.add_vertex!(hypergraph)
getnode(hypergraph::HyperGraph,index::Int64) = hypergraph.vertices[index]
Base.getindex(hypergraph::HyperGraph,node::HyperNode) = node
getnodes(hypergraph::HyperGraph) = hypergraph.vertices

#HyperEdge
Base.reverse(e::HyperEdge) = "A hyperedge does not support reverse()"
==(h1::HyperEdge,h2::HyperEdge) = collect(h1.vertices) ==  collect(h2.vertices)  #vertices are sorted when added

LightGraphs.add_edge!(graph::HyperGraph,vertices::HyperNode...) = add_hyperedge!(graph,vertices...)
gethypernodes(edge::HyperEdge) = collect(edge.vertices)

#Add new LOCAL HyperEdge to a HyperGraph
function add_hyperedge!(hypergraph::HyperGraph,hypernodes::HyperNode...)
    @assert length(hypernodes) > 1
    hypernodes = Set(collect(hypernodes))
    if has_edge(hypergraph,hypernodes)
        return hypergraph.hyperedges[hypernodes]
    else
        index = ne(hypergraph) + 1
        hyperedge = HyperEdge(hypernodes...)
        for hypernode in hypernodes
            push!(hypergraph.node_map[hypernode], hyperedge)
        end
        hypergraph.hyperedges[hypernodes] = hyperedge
        hypergraph.hyperedge_map[index] = hyperedge
        return hyperedge
    end
end
#Getters
gethyperedge(hypergraph::HyperGraph,edge_index::Int64) = hypergraph.hyperedge_map[edge_index]
gethyperedges(hypergraph::HyperGraph) = values(hypergraph.hyperedges)
getedges(hypergraph::HyperGraph) = gethyperedges(hypergraph)
LightGraphs.vertices(hyperedge::HyperEdge) = collect(hyperedge.vertices)
Base.getindex(hypergraph::HyperGraph,edge::HyperEdge) = edge.index

#LightGraphs Interface
LightGraphs.edges(graph::HyperGraph) = graph.hyperedges
LightGraphs.edgetype(graph::HyperGraph) = HyperEdge
LightGraphs.has_edge(graph::HyperGraph,edge::HyperEdge) = edge in values(graph.hyperedges)
LightGraphs.has_edge(graph::HyperGraph,hypernodes::Set{HyperNode}) = haskey(graph.hyperedges,hypernodes)
LightGraphs.has_vertex(graph::HyperGraph, v::Integer) = v in vertices(graph)
LightGraphs.is_directed(graph::HyperGraph) = false
LightGraphs.is_directed(::Type{HyperGraph}) = false
LightGraphs.ne(graph::HyperGraph) = length(graph.hyperedge_map)
LightGraphs.nv(graph::HyperGraph) = length(graph.vertices)
LightGraphs.vertices(graph::HyperGraph) = graph.vertices


#ANALYSIS FUNCTIONS
function LightGraphs.incidence_matrix(hypergraph::HyperGraph)
    I = []
    J = []
    for (edge_index,hyperedge) in hypergraph.hyperedge_map
        node_indices = sort(collect(hyperedge.vertices))
        for node_index in node_indices
            push!(I,node_index)
            push!(J,edge_index)
        end
    end
    V = Int.(ones(length(I)))
    return SparseArrays.sparse(I,J,V)
end
SparseArrays.sparse(hypergraph::HyperGraph) = LightGraphs.incidence_matrix(hypergraph)

#TODO adjacency_matrix
function LightGraphs.adjacency_matrix(hypergraph::HyperGraph)
    nothing
end

#NOTE Inefficient neighbors implementation
#Could use incidence matrix to do this faster
function LightGraphs.all_neighbors(g::HyperGraph,node::HyperNode)
    hyperedges = g.node_map[node]  #incident hyperedges to the hypernode
    neighbors = HyperNode[]
    for edge in hyperedges
        append!(neighbors,[vert for vert in edge.vertices if vert != node])
    end
    return unique(neighbors)
end

function incident_edges(g::HyperGraph,node::HyperNode)
    hyperedges = HyperEdge[]
    for hedge in g.node_map[node]
        push!(hyperedges,hedge)
    end
    return hyperedges
end

#Get all of the neighbors within a distance of a set of nodes
function neighborhood(g::HyperGraph,nodes::Vector{HyperNode},distance::Int64)
    V = collect(nodes)
    nbr = copy(V)
    newnbr = copy(V)
    oldnbr = []
    for k=1:distance
        for i in newnbr
            union!(nbr, all_neighbors(g,i))
        end
        union!(oldnbr,newnbr)
        newnbr = setdiff(nbr,oldnbr)
    end
    return nbr
end

function expand(g::HyperGraph,nodes::Vector{HyperNode},distance::Int64)
    new_nodes = neighborhood(g,nodes,distance)
    new_edges =  induced_edges(g,new_nodes)
    return new_nodes, new_edges
end

#Get the induced edges from a vector of hypernodes
function induced_edges(hypergraph::HyperGraph,hypernodes::Vector{HyperNode})
    external_nodes = setdiff(hypergraph.vertices,hypernodes) #nodes in hypergraph that aren't in hypernodes
    #Create partition matrix
    I = []
    J = []
    for hypernode in hypernodes
        j = getindex(hypergraph,hypernode)
        push!(I,1)
        push!(J,j)
    end
    for hypernode in external_nodes
        j = getindex(hypergraph,hypernode)
        push!(I,2)
        push!(J,j)
    end

    V = Int.(ones(length(J)))
    G = sparse(I,J,V)  #Node partition matrix
    A = sparse(hypergraph)
    C = G*A  #Edge partitions

    #FIND THE SHARED EDGES, Get indices of shared edges
    sum_vector = sum(C,dims = 1)
    max_vector = maximum(C,dims = 1)
    cross_vector = sum_vector - max_vector
    indices = findall(cross_vector .!= 0)                   #nonzero indices of the cross vector.  These are edges that cross partitions.
    indices = [indices[i].I[2] for i = 1:length(indices)]

    inds = findall(C[1,:] .!= 0)
    new_inds = filter(x -> !(x in indices), inds) #these are edge indices
    induced_edges = HyperEdge[gethyperedge(hypergraph,new_ind) for new_ind in new_inds]

    return induced_edges
end

#get the edges incident to a set of hypernodes. does not include edges induced by hypernodes
function incident_edges(hypergraph::HyperGraph,hypernodes::Vector{HyperNode})
    external_nodes = setdiff(hypergraph.vertices,hypernodes) #nodes in hypergraph that aren't in hypernodes
    #Create partition matrix
    I = []
    J = []
    for hypernode in hypernodes
        #j = getindex(hypergraph,hypernode)
        j = hypernode
        push!(I,1)
        push!(J,j)
    end
    for hypernode in external_nodes
        #j = getindex(hypergraph,hypernode)
        j = hypernode
        push!(I,2)
        push!(J,j)
    end

    V = Int.(ones(length(J)))
    G = sparse(I,J,V)  #Node partition matrix
    A = sparse(hypergraph)
    C = G*A  #Edge partitions

    #FIND THE SHARED EDGES, Get indices of shared edges
    sum_vector = sum(C,dims = 1)
    max_vector = maximum(C,dims = 1)
    cross_vector = sum_vector - max_vector
    indices = findall(cross_vector .!= 0)                   #nonzero indices of the cross vector.  These are edges that cross partitions.
    indices = [indices[i].I[2] for i = 1:length(indices)]

    incident_edges = HyperEdge[gethyperedge(hypergraph,index) for index in indices]

    return incident_edges
end

#Identify induced and incident edges
function identify_edges(hypergraph::HyperGraph,partitions::Vector{Vector{HyperNode}})
    nparts = length(partitions)

    #Create partition matrix
    I = []
    J = []
    for i = 1:nparts
       for hypernode in partitions[i]
           #j = getindex(hypergraph,hypernode)
           j = hypernode
           push!(I,i)
           push!(J,j)
       end
    end

    V = Int.(ones(length(J)))
    G = sparse(I,J,V)  #Node partition matrix
    A = sparse(hypergraph)
    C = G*A  #Edge partitions

    #FIND THE SHARED EDGES, Get indices of shared edges
    sum_vector = sum(C,dims = 1)
    max_vector = maximum(C,dims = 1)
    cross_vector = sum_vector - max_vector
    indices = findall(cross_vector .!= 0)                   #nonzero indices of the cross vector.  These are edges that cross partitions.
    indices = [indices[i].I[2] for i = 1:length(indices)]   #convert to Integers

    shared_edges = HyperEdge[]
    for index in indices
        push!(shared_edges,gethyperedge(hypergraph,index))
    end

    #GET INDUCED PARTITION EDGES (I.E GET THE EDGES LOCAL TO EACH PARTITION)
    partition_edges = Vector[Vector{HyperEdge}() for _ = 1:nparts]
    for i = 1:nparts
        inds = findall(C[i,:] .!= 0)
        new_inds = filter(x -> !(x in indices), inds) #these are edge indices
        for new_ind in new_inds
            push!(partition_edges[i],gethyperedge(hypergraph,new_ind))
        end
    end

    return partition_edges,shared_edges
end

#Partition Functions
function partition_list(hypergraph::HyperGraph,membership_vector::Vector)
    unique_parts = unique(membership_vector)
    unique_parts = sort(unique_parts)

    #map unique parts to partitions
    part_map = Dict()
    for (i,part) in enumerate(unique_parts)
        part_map[part] = i
    end

    nparts = length(unique_parts)
    partitions =[HyperNode[] for _ = 1:nparts]
    for (vertex,part) in enumerate(membership_vector)
        push!(partitions[part_map[part]],getnode(hypergraph,vertex))
    end
    return partitions
end

#LightGraphs.degree(g::HyperGraph,v::Int) = length(all_neighbors(g,v))

LightGraphs.rem_edge!(g::HyperGraph,e::HyperEdge) = throw(error("Edge removal not yet supported on hypergraphs"))
LightGraphs.rem_vertex!(g::HyperGraph) = throw(error("Vertex removal not yet supported on hypergraphs"))

####################################
#Print Functions
####################################
function string(graph::HyperGraph)
    "Hypergraph: "*"($(nv(graph)) , $(ne(graph)))"
end
print(io::IO, graph::HyperGraph) = print(io, string(graph))
show(io::IO,graph::HyperGraph) = print(io,graph)


function string(edge::HyperEdge)
    "HyperEdge: "*"$(collect(edge.vertices))"
end
print(io::IO,edge::HyperEdge) = print(io, string(edge))
show(io::IO,edge::HyperEdge) = print(io,edge)

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

function LightGraphs.adjacency_matrix(bgraph::BipartiteGraph)
    n_v1 = length(bgraph.vertexset1)
    n_v2 = length(bgraph.vertexset2)
    A = spzeros(n_v1,n_v2)
    for edge in edges(bgraph.graph)
        A[edge.src,edge.dst - n_v1] = 1
    end
    return A
end

function identify_separators(bgraph::BipartiteGraph,partitions::Vector;cut_selector = LightGraphs.degree)
    nparts = length(partitions)

    #Create partition matrix
    I = []
    J = []
    for i = 1:nparts
        for vertex in partitions[i]
           push!(I,i)
           push!(J,vertex)
        end
    end
    V = Int.(ones(length(J)))
    G = sparse(I,J,V)  #Node partition matrix
    A = LightGraphs.incidence_matrix(bgraph.graph)
    C = G*A  #Bipartite Edge Partitions

    #FIND THE SHARED NODES, Get indices of shared nodes
    sum_vector = sum(C,dims = 1)
    max_vector = maximum(C,dims = 1)
    cross_vector = sum_vector - max_vector
    indices = findall(cross_vector .!= 0)                   #nonzero indices of the cross vector.  These are edges that cross partitions.
    indices = [indices[i].I[2] for i = 1:length(indices)]   #index of cross edges

    #Assign boundary vertices to actual cross cuts (i.e. a vertex is a cut node or a cut edge)
    es = collect(LightGraphs.edges(bgraph.graph))
    cut_edges = es[indices]
    cross_elements = Int64[]
    for edge in cut_edges
        src = edge.src #src is always the true hypernode
        dst = edge.dst #dest is always the true hyperedge
        if cut_selector == :vertex
            push!(cross_elements,src)
        elseif cut_selector == :edge
            push!(cross_elements,dst)
        else #use slection function
            if cut_selector(bgraph.graph,src) >= cut_selector(bgraph.graph,dst)
                push!(cross_elements,src) #tie goes to vertex
            else
                push!(cross_elements,dst)
            end
        end
    end

    #GET INDUCED ELEMENTS: Need to remove the cut element from these lists
    partition_elements = Vector[Vector{Int64}() for _ = 1:nparts]
    for i = 1:nparts
        new_inds = filter(x -> !(x in cross_elements), partitions[i])
        for new_ind in new_inds
            push!(partition_elements[i],new_ind)
        end
    end

    return partition_elements,cross_elements
end

#TODO: try forwarding methods this way.  Causes ambiguous method calls....
# macro forward_bipartite_method(func)
#     return quote
#         function $(func)(bgraph::BipartiteGraph,args...)
#             output = $func(bgraph.graph,args...)
#             return output
#         end
#     end
# end
# @forward_bipartite_method(LightGraphs.all_neighbors)

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


"""
    identify_edges(hypergraph::HyperGraph,partitions::Vector{Vector{HyperNode}})

Identify both induced partition edges and cut edges given a partition of `HyperNode` vectors.
"""
function identify_edges(cgraph::CliqueGraph,partitions::Vector{Vector{Int64}})
    nparts = length(partitions)

    #Create partition matrix
    I = []
    J = []
    for i = 1:nparts
       for vertex in partitions[i]
           j = vertex
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

    graph_edges = collect(edges(cgraph))
    shared_edges = LightGraphs.Edge[]
    for index in indices
        push!(shared_edges,graph_edges[index])
    end

    #GET INDUCED PARTITION EDGES (I.E GET THE EDGES LOCAL TO EACH PARTITION)
    partition_edges = Vector[Vector{HyperEdge}() for _ = 1:nparts]
    for i = 1:nparts
        inds = findall(C[i,:] .!= 0)
        new_inds = filter(x -> !(x in indices), inds) #these are edge indices
        for new_ind in new_inds
            push!(partition_edges[i],graph_edges[new_ind])
        end
    end

    return partition_edges,shared_edges
end

"""
    identify_nodes(hypergraph::HyperGraph,partitions::Vector{Vector{HyperEdge}})

Identify both induced partition nodes and cut nodes given a partition of `HyperEdge` vectors.
"""
function identify_nodes(cgraph::CliqueGraph,partitions::Vector{Vector{LightGraphs.Edge}})
    nparts = length(partitions)
    graph_edges = collect(LightGraphs.edges(cgraph))
    edge_indices = Dict([(edge,j) for (j,edge) in enumerate(graph_edges)])

    #Create partition matrix
    I = []
    J = []
    for i = 1:nparts
       for edge in partitions[i]
           j = edge_indices[edge]   #getindex(hypergraph,hyperedge)
           push!(I,i)
           push!(J,j)
       end
    end

    V = Int.(ones(length(J)))
    G = sparse(I,J,V)  #Edge partition matrix
    A = incidence_matrix(hypergraph)
    C = A*G'  #Node Partitions

    #FIND THE SHARED NODES, Get indices of shared nodes
    sum_vector = sum(C,dims = 2)
    max_vector = maximum(C,dims = 2)
    cross_vector = sum_vector - max_vector
    indices = findall(cross_vector .!= 0)                   #nonzero indices of the cross vector.  These are edges that cross partitions.
    indices = [indices[i].I[1] for i = 1:length(indices)]   #convert to Integers

    shared_nodes= HyperNode[]
    for index in indices
        # push!(shared_nodes,getnode(hypergraph,index))
        push!(shared_nodes,index)
    end

    #GET INDUCED PARTITION NODES (I.E GET THE NODES LOCAL TO EACH PARTITION)
    partition_nodes = Vector[Vector{HyperNode}() for _ = 1:nparts]
    for i = 1:nparts
        inds = findall(C[:,i] .!= 0)
        new_inds = filter(x -> !(x in indices), inds) #these are edge indices
        for new_ind in new_inds
            # push!(partition_nodes[i],getnode(hypergraph,new_ind))
            push!(partition_nodes[i],new_ind)
        end
    end
    return partition_nodes,shared_nodes
end



"""
    identify_separators(cliquegraph::CliqueGraph,partitions::Vector{Vector{Int64})

Identify the edge cut separators given a vector of hypernode partitions. Returns induced elements (nodes and edges) and cut edges.

    identify_separators(cliquegraph::CliqueGraph,partitions::Vector{Vector{LightGraphs.Edge}})

Identify the node separators given a vector of hyperedge partitions. Returns induced elements (nodes and edges) and cut nodes.

"""
function identify_separators(cgraph::CliqueGraph,partitions::Vector{Vector{Int64}})
     induced_edges, cross_edges = identify_edges(cgraph,partitions)
     @assert length(induced_edges) == length(partitions)
     induced_elements = [[] for _ = 1:length(partitions)]
     for i = 1:length(partitions)
         append!(induced_elements[i],induced_edges[i])
         append!(induced_elements[i],partitions[i])
     end
     return induced_elements,cross_edges
end

function identify_separators(cgraph::CliqueGraph,partitions::Vector{Vector{LightGraphs.Edge}})
    incuded_nodes, cross_nodes = identify_nodes(cgraph,partitions)
    @assert length(induced_nodes) == length(partitions)
    induced_elements = [[] for _ = 1:length(partitions)]
    for i = 1:length(partitions)
        append!(induced_elements[i],induced_nodes[i])
        append!(induced_elements[i],partitions[i])
    end
    return induced_elements,cross_nodes
end

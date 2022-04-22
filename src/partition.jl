# The Partition object describes partitions of optinodes and optiedges.
# Different graph projections can be used to create a Partition object which is the standard interface to form subgraphs
abstract type AbstractPartition end
"""
    Partition(hypergraph::HyperGraph,node_membership_vector::Vector{Int64},ref_map::Dict)

Create a partition of optinodes using `hypergraph`, `node_membership_vector`, and 'ref_map'.  The 'ref_map' is a dictionary that maps hypernode indices (integers) and hyperedge indices (tuples) back to optinodes and optiedges.

    Partition(optigraph::OptiGraph,node_membership_vector::Vector{Int64},ref_map::Dict)

Create a partition using `optigraph`, `node_membership_vector`, and 'ref_map'. The `ref_map` is a mapping of node_indices to the original optinodes.

    Partition(optigraph::OptiGraph,optinode_vectors::Vector{Vector{OptiNode}})

Manually create a partition using `optigraph` and a vector of vectors containing sets of optinodes that represent each partition.
"""
mutable struct Partition <: AbstractPartition
    optinodes::Vector{OptiNode}   #optinodes at partition level
    optiedges::Vector{OptiEdge}   #optiedges at partition level
    subpartitions::Vector{AbstractPartition}      #subpartitions
end
Partition() = Partition(Vector{OptiNode}(),Vector{OptiEdge}(),Vector{Partition}())

function _check_valid_partition(graph::OptiGraph,optinode_vectors::Vector{Vector{OptiNode}})
    all_subnodes = vcat(optinode_vectors...)
    all_graph_nodes = all_nodes(graph)
    #nodes can only be in one partition
    length(all_subnodes) == length(union(all_subnodes)) || error("An optinode appears in multiple partition vectors. A partition requires distinct optinode vectors ")
    #all nodes must be in the optigraph
    all(node -> node in all_graph_nodes,all_subnodes) || error("The optinode vectors must contain all of the nodes in optigraph $graph")
    return true
end

function _check_valid_partition(graph::OptiGraph,optiedge_vectors::Vector{Vector{OptiEdge}})
    all_subedges = vcat(optiedge_vectors...)
    all_graph_edges = all_edges(graph)
    length(all_graph_edges) == length(union(all_subedges)) || error("An optiedge appears in multiple partition vectors. A partition requires distinct optiedge vectors")
    all(edge -> edge in all_graph_edges,all_subedges) || error("The optiedge vectors must contain all of the edges in optigraph $graph")
    return true
end

function _check_valid_partition(graph::OptiGraph,subgraphs::Vector{OptiGraph})
    all_subnodes = vcat(all_nodes.(subgraphs)...)
    all_graph_nodes = all_nodes(graph)

    all_subedges = vcat(all_edges.(subgraphs)...)
    all_graph_edges = all_edges(graph)

    all(node -> node in all_graph_nodes,all_subnodes) || error("The optinode vectors must contain all of the nodes in optigraph $graph")
    all(edge -> edge in all_graph_edges,all_subedges) || error("The optiedge vectors must contain all of the edges in optigraph $graph")
    length(all_subnodes) == length(union(all_subnodes)) || error("An optinode appears in multiple partition vectors. A partition requires distinct optinode vectors ")
    length(all_subedges) == length(union(all_subedges)) || error("An optiedge appears in multiple partition vectors. A partition requires distinct optiedge vectors")
    return true
end

#Partition using HyperGraph backend
function Partition(graph::OptiGraph,node_membership_vector::Vector{Int64})
    optinode_vectors = partition_list(graph,node_membership_vector)
    return Partition(graph,optinode_vectors)
end

#NODE PARTITION
#Partition with vectors of optinodes
function Partition(graph::OptiGraph,optinode_vectors::Vector{Vector{OptiNode}})
    _check_valid_partition(graph,optinode_vectors)

    partition = Partition()
    optiedge_vectors,cross_edges = identify_edges(graph,optinode_vectors)
    @assert length(optinode_vectors) == length(optiedge_vectors)
    partition.optiedges = cross_edges
    for i = 1:length(optinode_vectors)
        subpartition = Partition()
        subpartition.optinodes = optinode_vectors[i]
        subpartition.optiedges = optiedge_vectors[i]
        push!(partition.subpartitions,subpartition)
    end
    return partition
end

#EDGE PARTITION
#Partition with vectors of optiedges
function Partition(graph::OptiGraph,optiedge_vectors::Vector{Vector{OptiEdge}})
    _check_valid_partition(graph,optiedge_vectors)

    partition = Partition()
    optinode_vectors,cross_nodes = identify_nodes(graph,optiedge_vectors)
    @assert length(optinode_vectors) == length(optiedge_vectors)
    node_incident_edges = incident_edges(graph,cross_nodes) #incident edges to root partition nodes are also in root
    partition.optinodes = cross_nodes
    partition.optiedges = node_incident_edges
    for i = 1:length(optiedge_vectors)
        subpartition = Partition()
        subpartition.optinodes = optinode_vectors[i]
        subpartition.optiedges = setdiff(optiedge_vectors[i],node_incident_edges) #cut out the root incident edges
        push!(partition.subpartitions,subpartition)
    end
    return partition
end

#NODE-EDGE PARTITION
#Partition with subgraphs
function Partition(graph::OptiGraph,subgraphs::Vector{OptiGraph})
    _check_valid_partition(graph,subgraphs)

    n_parts = length(subgraphs)
    subnodes = vcat(all_nodes.(subgraphs)...)
    subedges = vcat(all_edges.(subgraphs)...)
    cross_nodes = filter(node -> !(node in subnodes),all_nodes(graph))
    cross_edges = filter(edge -> !(edge in subedges),all_edges(graph))
    node_incident_edges = incident_edges(graph,cross_nodes)

    partition = Partition()
    partition.optinodes = cross_nodes
    partition.optiedges = [node_incident_edges;cross_edges]
    for i = 1:length(subgraphs)
        subpartition = Partition()
        subpartition.optinodes = all_nodes(subgraphs[i])
        subpartition.optiedges = setdiff(all_edges(subgraphs[i]),node_incident_edges) #remove root incident edges
        push!(partition.subpartitions,subpartition)
    end
    return partition
end

########################################################################################################
#PARTITION USING DIFFERENT OPTIGRAPH REPRESENTATIONS (e.g. a hypergraph, cliquegraph, or bipartitegraph)
########################################################################################################
function Partition(graph::LightGraphs.AbstractGraph,membership_vector::Vector{Int64},ref_map::ProjectionMap;kwargs...)
    @assert graph == ref_map.projected_graph
    return Partition(membership_vector,ref_map;kwargs...)
end

function Partition(membership_vector::Vector{Int64},ref_map::ProjectionMap;kwargs...)
    optigraph = ref_map.optigraph
    partition_vectors = Plasmo._partition_list(membership_vector)
    induced = Plasmo.induced_elements(ref_map.projected_graph,partition_vectors;kwargs...)
    partition_elements = Plasmo._identify_partitions(induced,ref_map)  #could be optinode_vectors, optiedge_vectors, or subgraphs
    partition = Partition(optigraph,partition_elements)
    return partition
end

function _identify_partitions(induced_elements::Vector,ref_map::ProjectionMap)
    induced = [getindex.(Ref(ref_map),induced_elements[i]) for i = 1:length(induced_elements)]
    n_parts = length(induced)

    optinode_parts = Vector{Vector{OptiNode}}(undef,n_parts)
    optiedge_parts = Vector{Vector{OptiEdge}}(undef,n_parts)
    for i = 1:n_parts
        optinode_parts[i] = OptiNode[]
        optiedge_parts[i] = OptiEdge[]
    end
    for i = 1:n_parts
        for element in induced[i]
            if isa(element,OptiNode)
                push!(optinode_parts[i],element)
            elseif isa(element,OptiEdge)
                push!(optiedge_parts[i],element)
            end
        end
    end

    #Return either: optinode_vectors,optiedge_vector, or subgraphs
    if isempty(vcat(optiedge_parts...))
        return optinode_parts
    elseif isempty(vcat(optinode_parts...))
        return optiedge_parts
    else #create subgraphs to represent partition
        @assert !isempty(vcat(optiedge_parts...)) && !isempty(vcat(optinode_parts...))
        subgraphs = OptiGraph[]
        for i = 1:n_parts
            subgraph = OptiGraph(optinode_parts[i],optiedge_parts[i])
            push!(subgraphs,subgraph)
        end
        return subgraphs
    end
end

"""
    partition_list(graph::OptiGraph,membership_vector::Vector{Int64})

Return a list of optinode partitions given a `membership_vector`
"""
function partition_list(graph::OptiGraph,membership_vector::Vector{Int64})
    _init_graph_backend(graph)
    hypergraph,hyper_map = Plasmo.graph_backend_data(graph)
    partitions = _partition_list(membership_vector)
    return [getindex.(Ref(hyper_map),partitions[i]) for i = 1:length(partitions)]
end
@deprecate getpartitionlist partition_list

function partition_list(membership_vector::Vector{Int64},ref_map::ProjectionMap)
    partitions = partition_list(memebership_vector)
    return [getindex.(Ref(ref_map),partitions[i]) for i = 1:length(partitions)]
end

#convert membership_vector to a list of partitions
function _partition_list(membership_vector::Vector)
    unique_parts = unique(membership_vector)
    unique_parts = sort(unique_parts)

    #map unique parts to partitions
    part_map = Dict()
    for (i,part) in enumerate(unique_parts)
        part_map[part] = i
    end

    nparts = length(unique_parts)
    partitions =[Int64[] for _ = 1:nparts]
    for (vertex,part) in enumerate(membership_vector)
        push!(partitions[part_map[part]],vertex)
    end
    return partitions
end

##################################################################
#Partition object functions
##################################################################
getnodes(partition::Partition) = partition.optinodes
getedges(partition::Partition) = partition.optiedges
sub_partitions(partition::Partition) = partition.subpartitions

function all_subpartitions(partition::Partition)
    subparts = partition.subpartitions
    for part in subparts
        subparts = [subparts;all_subpartitions(part)]
    end
    return subparts
end

function n_subpartitions(partition::Partition)
    n_subparts = length(partition.subpartitions)
    subparts = partition.subpartitions
    for part in subparts
        n_subparts += n_subpartitions(part)
    end
    return n_subparts
end

#Create a new set of nodes on a optigraph
function _set_nodes(graph::OptiGraph,nodes::Vector{OptiNode})
    graph.optinodes = nodes
    for (idx,node) in enumerate(graph.optinodes)
        graph.node_idx_map[node] = idx
    end
    return nothing
end

#Create a new set of edges on a optigraph
function _set_edges(graph::OptiGraph,edges::Vector{OptiEdge})
    graph.optiedges = edges
    link_idx = 0
    for (idx,optiedge) in enumerate(graph.optiedges)
        graph.edge_idx_map[optiedge] = idx
        graph.optiedge_map[optiedge.nodes] = optiedge
    end
    return nothing
end

"""
    apply_partition!(optigraph::OptiGraph,partition::Partition)

Create subgraphs in `optigraph` using a `partition`.
"""
function apply_partition!(graph::OptiGraph,partition::Partition)
    root = partition
    graph.subgraphs = OptiGraph[]

    optinodes = root.optinodes
    optiedges = root.optiedges

    _set_nodes(graph,optinodes)
    _set_edges(graph,optiedges)

    subparts = root.subpartitions
    #Create subgraph structure from nodes and partition data
    for subpartition in subparts
        subgraph = OptiGraph()
        add_subgraph!(graph,subgraph)
        apply_partition!(subgraph,subpartition)
    end
    return nothing
end
@deprecate make_subgraphs! apply_partition!


#swap vertex and edge separators in the partition.  Return a new partition.
#IDEA TODO:
# function swap_separators!(graph::OptiGraph,partition::Partition)
# end


##################################################################
# Convenience partition functions.  These are meant to provide simple interfaces to generate hybrid partitions
##################################################################
#TODO: recursive partitions
"""
    partition_to_subgraphs!(optigraph::OptiGraph,partition_func::Function,args...;depth::Int64 = 1,kwargs...)

Create subgraphs in `optigraph` that form a `RECURSIVE_GRAPH` structure.
"""
function partition_to_subgraphs!(graph::OptiGraph,partition_func::Function,args...;depth::Int64 = 1,kwargs...)
    partitioned_graph,ref_map = hyper_graph(graph)
    membership_vector = partition_func(partitioned_graph,args...;kwargs...)
    partition = Partition(membership_vector,ref_map)
    apply_partition!(graph,partition)
    @assert graph_structure(graph) == RECURSIVE_GRAPH
    return nothing
end

"""
    partition_to_tree!(optigraph::OptiGraph,partition_func::Function,args...;depth::Int64 = 1,kwargs...)

Create subgraphs in `optigraph` that form a `RECURSIVE_TREE` structure.
"""
function partition_to_tree!(graph::OptiGraph,partition_func::Function,args...;depth = 1,kwargs...) #method = :edge_hypergraph
    partitioned_graph,ref_map = edge_hyper_graph(graph)
    membership_vector = partition_func(partitioned_graph,args...;kwargs...)
    partition = Partition(membership_vector,ref_map)
    apply_partition!(graph,partition)
    @assert graph_structure(graph) == RECURSIVE_TREE
end

"""
    partition_to_tree!(optigraph::OptiGraph,partition_func::Function,args...;depth::Int64 = 1,kwargs...)

Create subgraphs in `optigraph` that form a `RECURSIVE_TREE` structure.
"""
function partition_to_linked_tree!(graph::OptiGraph,partition_func::Function,args...;depth = 1,kwargs...)
    partitioned_graph,ref_map = bipartite_graph(graph)
    membership_vector = partition_func(partitioned_graph,args...;kwargs...)
    partition = Partition(membership_vector,ref_map)
    apply_partition!(graph,partition)
    @assert graph_structure(graph) in [RECURSIVE_TREE,RECURSIVE_GRAPH,RECURSIVE_LINKED_TREE]
end

####################################
#Print Functions
####################################
string(partition::Partition) = "OptiGraph Partition w/ $(n_subpartitions(partition)) subpartitions"
print(io::IO, partition::Partition) = print(io, string(partition))
show(io::IO,partition::Partition) = print(io,partition)

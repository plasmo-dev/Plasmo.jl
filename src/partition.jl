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

#TODO: Check partition structure
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
    length(all_edges) == length(union(all_subedges)) || error("An optiedge appears in multiple partition vectors. A partition requires distinct optiedge vectors")
    all(edge -> edge in all_graph_edges,all_subedges) || error("The optiedge vectors must contain all of the edges in optigraph $graph")
    return true
end

function _check_valid_partition(graph::OptiGraph,subgraphs::Vector{OptiGraph})
    all_subnodes = vcat(all_nodes.(subgraphs))
    all_graph_nodes = all_nodes(graph)

    all_subedges = vcat(all_edges.(subgraphs))
    all_graph_edges = all_edges(graph)

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
function Partition(graph::OptiGraph,subgraphs::Vector{OptiGraph})
    _check_valid_partition(graph,subgraphs)
    n_parts = length(subgraphs)
    subnodes = vcat(all_nodes.(subgraphs)...)
    subedges = vcat(all_edges.(subgraphs)...)
    cross_nodes = filter(node -> !node in subnodes,all_nodes(graph))
    cross_edges = filter(edge -> !edge in subedges,all_edges(graph))
    node_incident_edges = incident_edges(graph,cross_nodes)

    partition = Partition()
    partition.optinodes = cross_nodes
    partition.optiedges = [node_incident_edges;cross_edges]
    for i = 1:length(optiedge_vectors)
        subpartition = Partition()
        subpartition.optinodes = subnodes[i]
        subpartition.optiedges = setdiff(subedges[i],node_incident_edges) #cut out the root incident edges
        push!(partition.subpartitions,subpartition)
    end
    return partition
end

##################################################################
#PARTITION USING DIFFERENT OPTIGRAPH REPRESENTATIONS (e.g. a hypergraph, cliquegraph, or bipartitegraph)
##################################################################
function Partition(graph::LightGraphs.AbstractGraph,membership_vector::Vector{Int64},ref_map::Dict)
    partition_elements = _partition_list(membership_vector)
    induced_elements,cross_elements = identify_separators(graph,partition_elements)
    partition = Partition(induced_elements,cross_elements,ref_map)
    return partition
end

#Partition(partition_elements::Vector{Vector},induced_elements::Vector{Vector},cross_elements::Vector,ref_map::Dict)
function Partition(induced_elements::Vector,cross_elements::Vector,ref_map::Dict)
    partition = Partition()
    subpart_optinodes,subpart_optiedges = identify_induced_elements(induced_elements,ref_map)
    cross_nodes,cross_edges = identify_cross_elements(cross_elements,ref_map)

    partition.optinodes = cross_nodes
    partition.optiedges = cross_edges
    for i = 1:length(induced_elements)
        subpartition = Partition()
        subpartition.optinodes = subpart_optinodes[i]
        subpartition.optiedges = subpart_optiedges[i]
        push!(partition.subpartitions,subpartition)
    end

    return partition
end

#Identify cross elements
function identify_cross_elements(elements::Vector where T,ref_map::Dict)
    optinodes = OptiNode[]
    optiedges = OptiEdge[]
    opti_elements = getindex.(Ref(ref_map),elements)

    for element in opti_elements
        if isa(element,OptiNode)
            push!(optinodes,element)
        elseif isa(element,OptiEdge)
            push!(optiedges,element)
        end
    end
    return optinodes,optiedges
end

#Identify partition elements
function identify_induced_elements(induced_elements::Vector where T,ref_map::Dict)
    induced = [getindex.(Ref(ref_map),induced_elements[i]) for i = 1:length(induced_elements)]
    n_parts = length(induced)

    optinode_parts = Vector{Vector}(undef,n_parts)
    optiedge_parts = Vector{Vector}(undef,n_parts)
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
    return optinode_parts,optiedge_parts
end

"""
    partition_list(graph::OptiGraph,membership_vector::Vector{Int64})

Return a list of optinode partitions given a `membership_vector`
"""
function partition_list(graph::OptiGraph,membership_vector::Vector{Int64})
    _init_graph_backend(graph)
    hypergraph,hyper_map = Plasmo.graph_backend_data(graph)
    partitions = _partition_list(memebership_vector)
    return [getindex.(Ref(hyper_map),partitions[i] for i = 1:length(partitions))]
end
@deprecate getpartitionlist partition_list

function partition_list(membership_vector::Vector{Int64},ref_map::Dict)
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
#Partition object access functions
##################################################################
getnodes(partition::Partition) = partition.optinodes
getedges(partition::Partition) = partition.optiedges
getsubpartitions(partition::Partition) = partition.subpartitions

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


#apply a partition to an optigraph
"""
    make_subgraphs!(optigraph::OptiGraph,partition::Partition)

Create subgraphs in `optigraph` using a 'partition'.
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

####################################
#Print Functions
####################################
function string(partition::Partition)
    """
        OptiGraph Partition w/ $(n_subpartitions(partition)) subpartitions
    """
end
print(io::IO, partition::Partition) = print(io, string(partition))
show(io::IO,partition::Partition) = print(io,partition)


# function Partition(graph::OptiGraph,optinode_vectors::Vector{Vector{OptiNode}},optiedge_vectors::Vector{Vector{OptiEdge}})
#     partition = Partition()
#     @assert length(optinode_vectors) == length(optiedge_vectors)
#     optinode_vectors,cross_nodes = identify_nodes(graph,optiedge_vectors)
# end

# #HYPERGRAPH PARTITION
# #Partition with a HyperGraph and a reference map
# function Partition(hypergraph::HyperGraph,node_membership_vector::Vector{Int64},ref_map::Dict)
#     partition = Partition()
#     hypernode_vectors = _partition_list(node_membership_vector)
#
#     induced_edge_partitions,cross_edges = identify_edges(hypergraph,hypernode_vectors)
#     @assert length(hypernode_vectors) == length(induced_edge_partitions)
#
#     partition.optiedges = getindex.(Ref(ref_map),cross_edges)
#     for i = 1:length(hypernode_vectors)
#         subpartition = Partition()
#         subpartition.optinodes = getindex.(Ref(ref_map),hypernode_vectors[i])
#         subpartition.optiedges = getindex.(Ref(ref_map),induced_edge_partitions[i])
#         push!(partition.subpartitions,subpartition)
#     end
#     return partition
# end

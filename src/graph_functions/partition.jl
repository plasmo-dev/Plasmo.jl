"""
    Partition

A data structure that describes a (possibly recursive) graph partition.
"""
mutable struct Partition
    optinodes::Vector{OptiNode}
    optiedges::Vector{OptiEdge}
    subpartitions::Vector{Partition}
end

function Partition()
    return Partition(Vector{OptiNode}(), Vector{OptiEdge}(), Vector{Partition}())
end

"""
    build_partition_list(hyper::HyperGraphProjection, membership_vector::Vector{Int64})

Return a list of optinode partitions given a `membership_vector`
"""
function build_partition_list(hyper::HyperGraphProjection, membership_vector::Vector{Int64})
    partitions = _build_partition_list(membership_vector)
    return get_mapped_elements.(Ref(hyper), partitions)
end
@deprecate getpartitionlist get_partition_list
@deprecate partition_list get_partition_list

#
# Partition constructors
#

"""
    Partition(graph::OptiGraph, node_membership_vector::Vector{Int64})

Create a partition directly from a vector of integers.
"""
function Partition(graph::OptiGraph, node_membership_vector::Vector{Int64})
    hyper = hyper_projection(graph)
    optinode_vectors = build_partition_list(hyper, node_membership_vector)
    return _build_hypernode_partition(graph, optinode_vectors, hyper)
end

"""
    Partition(graph::OptiGraph, optinode_vectors::Vector{Vector{OptiNode}})

Manually create a partition using `graph` and a vector of vectors containing sets 
of optinodes that represent each partition.
"""
function Partition(graph::OptiGraph, optinode_vectors::Vector{<:Vector{<:OptiNode}})
    _check_valid_partition(graph, optinode_vectors)
    hyper = hyper_projection(graph)
    return _build_hypernode_partition(graph, optinode_vectors, hyper)
end

"""
    Partition(graph::OptiGraph, optiedge_vectors::Vector{Vector{OptiEdge}})

Manually create a partition using `graph` and a vector of vectors containing sets 
of optiedges that represent each partition.
"""
function Partition(graph::OptiGraph, optiedge_vectors::Vector{<:Vector{<:OptiEdge}})
    _check_valid_partition(graph, optiedge_vectors)
    hyper = hyper_projection(graph)
    optinode_vectors, cross_nodes = identify_nodes(hyper, optiedge_vectors)
    @assert length(optinode_vectors) == length(optiedge_vectors)
    node_incident_edges = incident_edges(hyper, cross_nodes) #incident edges to root partition nodes are also in root

    partition = Partition()
    partition.optinodes = cross_nodes
    partition.optiedges = node_incident_edges
    for i in 1:length(optiedge_vectors)
        subpartition = Partition()
        subpartition.optinodes = optinode_vectors[i]
        subpartition.optiedges = setdiff(optiedge_vectors[i], node_incident_edges) #cut out the root incident edges
        push!(partition.subpartitions, subpartition)
    end
    return partition
end

"""
    Partition(graph::OptiGraph, subgraphs::Vector{OptiGraph})

Manually create a partition using `graph` and a vector subgraphs which represent 
the partitions.
"""
function Partition(graph::OptiGraph, subgraphs::Vector{GT}) where {GT<:AbstractOptiGraph}
    _check_valid_partition(graph, subgraphs)
    hyper = hyper_projection(graph)
    n_parts = length(subgraphs)
    subnodes = vcat(all_nodes.(subgraphs)...)
    subedges = vcat(all_edges.(subgraphs)...)
    cross_nodes = filter(node -> !(node in subnodes), all_nodes(graph))
    cross_edges = filter(edge -> !(edge in subedges), all_edges(graph))
    node_incident_edges = incident_edges(hyper, cross_nodes)

    partition = Partition()
    partition.optinodes = cross_nodes
    partition.optiedges = [node_incident_edges; cross_edges]
    for i in 1:length(subgraphs)
        subpartition = Partition()
        subpartition.optinodes = all_nodes(subgraphs[i])
        subpartition.optiedges = setdiff(all_edges(subgraphs[i]), node_incident_edges) #remove root incident edges
        push!(partition.subpartitions, subpartition)
    end
    return partition
end

"""
    Partition(projection::GraphProjection, membership_vector::Vector{Int64}; kwargs...)

Partition using different optigraph projections
"""
function Partition(projection::GraphProjection, membership_vector::Vector{Int64}; kwargs...)
    optigraph = projection.optigraph
    partition_vectors = _build_partition_list(membership_vector)
    induced = _induced_elements(projection.projected_graph, partition_vectors; kwargs...)

    # NOTE: elements could be optinode_vectors, optiedge_vectors, or subgraphs
    partition_elements = _identify_partitions(projection, induced)
    partition = Partition(optigraph, partition_elements)
    return partition
end

#
# partition utilities
#

function _check_valid_partition(
    graph::OptiGraph, optinode_vectors::Vector{<:Vector{<:OptiNode}}
)
    all_subnodes = vcat(optinode_vectors...)
    all_graph_nodes = all_nodes(graph)

    #nodes can only be in one partition
    length(all_subnodes) == length(union(all_subnodes)) ||
        error("An optinode appears in multiple partition vectors. 
              A partition requires distinct optinode vectors ")

    #all nodes must be in the optigraph
    all(node -> node in all_graph_nodes, all_subnodes) ||
        error("The optinode vectors must contain all of the nodes in optigraph $graph")
    return true
end

function _check_valid_partition(
    graph::OptiGraph, optiedge_vectors::Vector{<:Vector{<:OptiEdge}}
)
    all_subedges = vcat(optiedge_vectors...)
    all_graph_edges = all_edges(graph)
    length(all_graph_edges) == length(union(all_subedges)) || error(
        "An optiedge appears in multiple partition vectors. A partition requires distinct optiedge vectors",
    )
    all(edge -> edge in all_graph_edges, all_subedges) ||
        error("The optiedge vectors must contain all of the edges in optigraph $graph")
    return true
end

function _check_valid_partition(
    graph::OptiGraph, subgraphs::Vector{GT}
) where {GT<:AbstractOptiGraph}
    all_subnodes = vcat(all_nodes.(subgraphs)...)
    all_graph_nodes = all_nodes(graph)

    all_subedges = vcat(all_edges.(subgraphs)...)
    all_graph_edges = all_edges(graph)

    all(node -> node in all_graph_nodes, all_subnodes) ||
        error("The optinode vectors must contain all of the nodes in optigraph $graph")
    all(edge -> edge in all_graph_edges, all_subedges) ||
        error("The optiedge vectors must contain all of the edges in optigraph $graph")
    length(all_subnodes) == length(union(all_subnodes)) || error(
        "An optinode appears in multiple partition vectors. A partition requires distinct optinode vectors ",
    )
    length(all_subedges) == length(union(all_subedges)) || error(
        "An optiedge appears in multiple partition vectors. A partition requires distinct optiedge vectors",
    )
    return true
end

function _check_valid_partition(graph::OptiGraph, partition::Partition)
    return isempty(setdiff(all_nodes(graph), all_nodes(partition))) || error(
        "Invalid partition for graph. All optigraph nodes must be within the partition."
    )
end

function _induced_elements(graph::GOI.HyperGraph, partitions::Vector)
    return GOI.induced_elements(graph, partitions)
end

function _induced_elements(graph::GOI.BipartiteGraph, partitions::Vector; kwargs...)
    return GOI.induced_elements(graph, partitions; kwargs...)
end

function _induced_elements(graph::Graphs.Graph, partitions::Vector)
    return partitions
end

function _identify_partitions(projection::GraphProjection, induced_elements::Vector)
    induced = get_mapped_elements.(Ref(projection), induced_elements)
    n_parts = length(induced)
    optinode_parts = Vector{Vector{OptiNode}}(undef, n_parts)
    optiedge_parts = Vector{Vector{OptiEdge}}(undef, n_parts)
    for i in 1:n_parts
        optinode_parts[i] = OptiNode[]
        optiedge_parts[i] = OptiEdge[]
    end
    for i in 1:n_parts
        for element in induced[i]
            if isa(element, OptiNode)
                push!(optinode_parts[i], element)
            elseif isa(element, OptiEdge)
                push!(optiedge_parts[i], element)
            end
        end
    end

    # return either: optinode_vectors, optiedge_vector, or subgraphs
    if isempty(vcat(optiedge_parts...))
        return optinode_parts
    elseif isempty(vcat(optinode_parts...))
        return optiedge_parts
    else
        # create subgraphs to represent partition
        @assert !isempty(vcat(optiedge_parts...)) && !isempty(vcat(optinode_parts...))
        subgraphs = OptiGraph[]
        for i in 1:n_parts
            # NOTE: we do not enforce a valid optigraph here
            subgraph = _assemble_optigraph(optinode_parts[i], optiedge_parts[i])
            push!(subgraphs, subgraph)
        end
        return subgraphs
    end
end

function _build_hypernode_partition(
    graph::OptiGraph,
    optinode_vectors::Vector{<:Vector{<:OptiNode}},
    hyper::HyperGraphProjection,
)
    optiedge_vectors, cross_edges = identify_edges(hyper, optinode_vectors)
    @assert length(optinode_vectors) == length(optiedge_vectors)

    partition = Partition()
    partition.optiedges = cross_edges
    for i in 1:length(optinode_vectors)
        subpartition = Partition()
        subpartition.optinodes = optinode_vectors[i]
        subpartition.optiedges = optiedge_vectors[i]
        push!(partition.subpartitions, subpartition)
    end
    return partition
end

"""
    _build_partition_list(membership_vector::Vector)

Convert a vector of membership ids to a list of partitions
"""
function _build_partition_list(membership_vector::Vector)
    unique_parts = unique(membership_vector)
    unique_parts = sort(unique_parts)

    #map unique parts to partitions
    part_map = Dict()
    for (i, part) in enumerate(unique_parts)
        part_map[part] = i
    end

    nparts = length(unique_parts)
    partitions = [Int64[] for _ in 1:nparts]
    for (vertex, part) in enumerate(membership_vector)
        push!(partitions[part_map[part]], vertex)
    end
    return partitions
end

#
# partition methods
#

function all_subpartitions(partition::Partition)
    subparts = partition.subpartitions
    for part in subparts
        subparts = [subparts; all_subpartitions(part)]
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

function all_nodes(partition::Partition)
    nodes = partition.optinodes
    for subpartition in partition.subpartitions
        nodes = [nodes; all_nodes(subpartition)]
    end
    return nodes
end

"""
    Assemble a new optigraph from a given `Partition`.
"""
function assemble_optigraph(partition::Partition; name=nothing)
    new_graph = _assemble_optigraph(partition.optinodes, partition.optiedges)
    for subpartition in partition.subpartitions
        subgraph = _assemble_optigraph(subpartition.optinodes, subpartition.optiedges)
        add_subgraph(new_graph, subgraph)
    end
    if name != nothing
        JuMP.set_name(new_graph, name)
    end
    return new_graph
end

"""
    apply_partition!(graph::OptiGraph, partition::Partition)

Generate subgraphs in an optigraph using a partition.
"""
function apply_partition!(graph::OptiGraph, partition::Partition)
    _check_valid_partition(graph, partition)

    graph.optinodes = OrderedSet(partition.optinodes)
    graph.optiedges = OrderedSet(partition.optiedges)
    graph.subgraphs = OrderedSet{OptiGraph}()

    # create new subgraphs
    _make_subgraphs!(graph, partition)

    # create a new top-level graph we use to assemble a new backend
    temp_graph = _assemble_optigraph(partition.optinodes, partition.optiedges)
    graph.backend = temp_graph.backend
    graph.backend.optigraph = graph

    # TODO: filter nodes and edges that actually need to be transferred
    # it is possible a node or edge source is defined in another graph.
    _transfer_elements!(graph, partition)

    return nothing
end

"""
    _make_subgraphs!(graph::OptiGraph, partition::Partition)

Create new subgraphs in an optigraph using a `Partition`
"""
function _make_subgraphs!(graph::OptiGraph, partition::Partition)
    for subpartition in partition.subpartitions
        subgraph = _assemble_optigraph(subpartition.optinodes, subpartition.optiedges)
        add_subgraph(graph, subgraph)
        _transfer_elements!(subgraph, subpartition)
        _make_subgraphs!(subgraph, subpartition)
    end
    return nothing
end

function _transfer_elements!(new_graph::OptiGraph, partition::Partition)
    for node in partition.optinodes
        _transfer_element!(new_graph, node)
    end
    for edge in partition.optiedges
        _transfer_element!(new_graph, edge)
    end
    return nothing
end

"""
    Transfer optinode backend to a new graph
"""
function _transfer_element!(new_graph::OptiGraph, node::OptiNode)
    # TODO: make sure `new_graph` has a backend to point to
    source = source_graph(node)

    # update object dictionary
    # node_dict = JuMP.object_dictionary(node)
    node_dict = node_object_dictionary(node) # NOTE: will be slow for large partitions
    merge!(new_graph.element_data.node_obj_dict, node_dict)
    new_graph.element_data.node_to_graphs[node] = source.element_data.node_to_graphs[node]

    # transfer element data
    _transfer_element_data!(new_graph, node)

    # delete the node_to_graphs reference since new_graph is now the source graph
    delete!(new_graph.element_data.node_to_graphs, node)

    # also delete source reference, since it gets created in _make_subgraphs!
    delete!(source.element_data.node_to_graphs, node)

    # clean up the source graph
    for key in keys(node_dict)
        delete!(source.element_data.node_obj_dict, key)
    end

    # update the node source reference
    node.source_graph.x = new_graph
    return nothing
end

# TODO: copy over relevant element data
function _transfer_element_data!(new_graph::OptiGraph, node::OptiNode) end

"""
    Transfer optiedge ownership to new optigraph 
"""
function _transfer_element!(new_graph::OptiGraph, edge::OptiEdge)
    source = source_graph(edge)
    edge_dict = edge_object_dictionary(edge) #JuMP.object_dictionary(edge)
    new_graph.element_data.edge_to_graphs[edge] = source.element_data.edge_to_graphs[edge]

    # delete the edge_to_graphs reference since new_graph is now the source graph
    delete!(new_graph.element_data.edge_to_graphs, edge)

    # also delete source reference, since it gets created in _make_subgraphs!
    delete!(source.element_data.edge_to_graphs, edge)

    # clean up the source graph
    for key in keys(edge_dict)
        delete!(source.element_data.edge_obj_dict, key)
    end

    # update the edge source reference
    edge.source_graph.x = new_graph
    return nothing
end

#IDEA: swap vertex and edge separators in the partition.  Return a new partition.
#function swap_separators(graph::OptiGraph, partition::Partition)
#end

# ##################################################################
# # Convenience partition functions.  
# # These are simple interfaces to generate hybrid partitions
# # TODO: recursive partitions
# ##################################################################
# """
#     partition_to_subgraphs!(optigraph::OptiGraph,partition_func::Function,args...; kwargs...)

# Create subgraphs in `optigraph` that form a `RECURSIVE_GRAPH` structure.
# """
# function partition_to_subgraphs!(
#     graph::OptiGraph, partition_func::Function, args...; kwargs...
# )
#     hyper = hyper_projection(graph)
#     membership_vector = partition_func(hyper.projected_graph, args...; kwargs...)
#     partition = Partition(projection, membership_vector)
#     apply_partition!(graph, partition)
#     return nothing
# end

# """
#     partition_to_tree!(optigraph::OptiGraph,partition_func::Function,args...; kwargs...)

# Create subgraphs in `optigraph` that form a `RECURSIVE_TREE` structure.
# """
# function partition_to_tree!(graph::OptiGraph, partition_func::Function, args...; kwargs...)
#     projection = build_edge_hyper_graph(graph)
#     membership_vector = partition_func(projection.projected_graph, args...; kwargs...)
#     partition = Partition(projection, membership_vector)
#     apply_partition!(graph, partition)
#     return nothing
# end

# """
#     partition_to_tree!(optigraph::OptiGraph,partition_func::Function,args...; kwargs...)

# Create subgraphs in `optigraph` that form a `RECURSIVE_TREE` structure.
# """
# function partition_to_subgraph_tree!(
#     graph::OptiGraph, partition_func::Function, args...; kwargs...
# )
#     projection = build_bipartite_graph(graph)
#     membership_vector = partition_func(projection.projected_graph, args...; kwargs...)
#     partition = Partition(projection, membership_vector)
#     return apply_partition!(graph, partition)
# end

# function Base.string(partition::Partition)
#     return "OptiGraph Partition w/ $(n_subpartitions(partition)) subpartitions"
# end
# Base.print(io::IO, partition::Partition) = Base.print(io, string(partition))
# Base.show(io::IO, partition::Partition) = Base.print(io, partition)

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
    to_partition_list(hyper::HyperGraphProjection, membership_vector::Vector{Int64})

Return a list of optinode partitions given a `membership_vector`
"""
function to_partition_list(hyper::HyperGraphProjection, membership_vector::Vector{Int64})
    partitions = _build_partition_list(membership_vector)
    return get_mapped_elements.(Ref(hyper), partitions)
end
@deprecate getpartitionlist to_partition_list
@deprecate partition_list to_partition_list

function _check_valid_partition(
    graph::OptiGraph, optinode_vectors::Vector{Vector{OptiNode}}
)
    all_subnodes = vcat(optinode_vectors...)
    all_graph_nodes = all_nodes(graph)

    #nodes can only be in one partition
    length(all_subnodes) == length(union(all_subnodes)) || error(
        "An optinode appears in multiple partition vectors. 
        A partition requires distinct optinode vectors ",
    )

    #all nodes must be in the optigraph
    all(node -> node in all_graph_nodes, all_subnodes) ||
        error("The optinode vectors must contain all of the nodes in optigraph $graph")
    return true
end

function _check_valid_partition(
    graph::OptiGraph, optiedge_vectors::Vector{Vector{OptiEdge}}
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

function _check_valid_partition(graph::OptiGraph, subgraphs::Vector{OptiGraph})
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

"""
    Partition(graph::OptiGraph, node_membership_vector::Vector{Int64})

Create a partition directly from a `node_membership_vector`.
"""
function Partition(graph::OptiGraph, node_membership_vector::Vector{Int64})
    hyper = build_hypergraph(graph)
    optinode_vectors = to_partition_list(hyper, node_membership_vector)
    return _build_hypernode_partition(graph, optinode_vectors, hyper)
end

"""
    Partition(graph::OptiGraph, optinode_vectors::Vector{Vector{OptiNode}})

Manually create a partition using `graph` and a vector of vectors containing sets 
of optinodes that represent each partition.
"""
function Partition(
    graph::OptiGraph, 
    optinode_vectors::Vector{Vector{OptiNode}}
)
    _check_valid_partition(graph, optinode_vectors)
    hyper = build_hypergraph(graph)
    return _build_hypernode_partition(graph, optinode_vectors, hyper)
end

function _build_hypernode_partition(
    graph::OptiGraph, 
    optinode_vectors::Vector{Vector{OptiNode}},
    hyper::HyperGraphProjection
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
    Partition(graph::OptiGraph, optiedge_vectors::Vector{Vector{OptiEdge}})

Manually create a partition using `graph` and a vector of vectors containing sets 
of optiedges that represent each partition.
"""
function Partition(graph::OptiGraph, optiedge_vectors::Vector{Vector{OptiEdge}})
    _check_valid_partition(graph, optiedge_vectors)
    hyper = build_hypergraph(graph)
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
function Partition(graph::OptiGraph, subgraphs::Vector{OptiGraph})
    _check_valid_partition(graph, subgraphs)
    hyper = build_hypergraph(graph)
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

    #Return either: optinode_vectors,optiedge_vector, or subgraphs
    if isempty(vcat(optiedge_parts...))
        return optinode_parts
    elseif isempty(vcat(optinode_parts...))
        return optiedge_parts
    else #create subgraphs to represent partition
        @assert !isempty(vcat(optiedge_parts...)) && !isempty(vcat(optinode_parts...))
        subgraphs = OptiGraph[]
        for i in 1:n_parts
            subgraph = OptiGraph(optinode_parts[i], optiedge_parts[i])
            push!(subgraphs, subgraph)
        end
        return subgraphs
    end
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

# Partition object functions
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

# TODO: re-write completely
# This function would potentially delete subgraph backends depending on how the  
# user chose to model their problem. A lot can happen here.
"""
    apply_partition!(graph::OptiGraph, partition::Partition)

Generate subgraphs in an optigraph using a partition.

NOTE: this could be a destructive operation in the sense that node and edge references
will change.
"""
function apply_partition!(
    graph::OptiGraph, 
    partition::Partition; 
    create_subgraph_backends=false
)
    # NOTE: Create new graph backends; then populate with partition information.
    # if we set `create_subgraph_backends = true`, then we transfer nodes and edges to 
    # new source graphs (this changes their optigraph reference).

    # create graph backend
    new_backend = GraphBackend(graph)

    # Re-create existing nodes on new backend?

    # populate backend with root nodes and edges

    root = partition
    graph.optinodes = root.optinodes
    graph.optiedges = root.optiedges

    # update the backend mapping for root graph
    # _set_nodes(graph, optinodes)
    # _set_edges(graph, optiedges)

    # clear subgraphs
    graph.subgraphs = OptiGraph[]
    for subpart in root.subpartitions
        subgraph = OptiGraph()
        add_subgraph!(graph, subgraph)
        # copy partition data into subgraphs

        #apply_partition!(subgraph, subpart)
    end

    # graph.backend = new_backend
    # delete old backend

    return
end
@deprecate make_subgraphs! apply_partition!

#IDEA: swap vertex and edge separators in the partition.  Return a new partition.
#function swap_separators!(graph::OptiGraph, partition::Partition)
#end

##################################################################
# Convenience partition functions.  
# These are simple interfaces to generate hybrid partitions
# TODO: recursive partitions
##################################################################
"""
    partition_to_subgraphs!(optigraph::OptiGraph,partition_func::Function,args...; kwargs...)

Create subgraphs in `optigraph` that form a `RECURSIVE_GRAPH` structure.
"""
function partition_to_subgraphs!(
    graph::OptiGraph, partition_func::Function, args...; kwargs...
)
    hyper = build_hypergraph(graph)
    membership_vector = partition_func(hyper.projected_graph, args...; kwargs...)
    partition = Partition(projection, membership_vector)
    apply_partition!(graph, partition)
    return
end

"""
    partition_to_tree!(optigraph::OptiGraph,partition_func::Function,args...; kwargs...)

Create subgraphs in `optigraph` that form a `RECURSIVE_TREE` structure.
"""
function partition_to_tree!(
    graph::OptiGraph, partition_func::Function, args...; kwargs...
)
    projection = build_edge_hyper_graph(graph)
    membership_vector = partition_func(projection.projected_graph, args...; kwargs...)
    partition = Partition(projection, membership_vector)
    apply_partition!(graph, partition)
    return
end

"""
    partition_to_tree!(optigraph::OptiGraph,partition_func::Function,args...; kwargs...)

Create subgraphs in `optigraph` that form a `RECURSIVE_TREE` structure.
"""
function partition_to_subgraph_tree!(
    graph::OptiGraph, partition_func::Function, args...; kwargs...
)
    projection = build_bipartite_graph(graph)
    membership_vector = partition_func(projection.projected_graph, args...; kwargs...)
    partition = Partition(projection, membership_vector)
    return apply_partition!(graph, partition)
end


function Base.string(partition::Partition)
    return "OptiGraph Partition w/ $(n_subpartitions(partition)) subpartitions"
end
Base.print(io::IO, partition::Partition) = Base.print(io, string(partition))
Base.show(io::IO, partition::Partition) = Base.print(io, partition)


# #Create a new set of nodes on a optigraph
# function _set_nodes(graph::OptiGraph, nodes::Vector{OptiNode})
#     graph.optinodes = nodes
#     for (idx, node) in enumerate(graph.optinodes)
#         graph.node_idx_map[node] = idx
#     end
#     return nothing
# end

# #Create a new set of edges on a optigraph
# function _set_edges(graph::OptiGraph, edges::Vector{OptiEdge})
#     graph.optiedges = edges
#     link_idx = 0
#     for (idx, optiedge) in enumerate(graph.optiedges)
#         graph.edge_idx_map[optiedge] = idx
#         graph.optiedge_map[optiedge.nodes] = optiedge
#     end
#     return nothing
# end
struct GraphBackend
    lightgraph::LightGraphs.AbstractGraph
    graph_map::Dict
end
function GraphBackend(optigraph::OptiGraph)
    hyper_graph,hyper_map = hypergraph(optigraph)
    backend = GraphBackend(hyper_graph,hyper_map)
end

function set_graph_backend(graph::OptiGraph,backend::GraphBackend = GraphBackend())
    graph.graph_backend = backend
end
graph_backend(graph::OptiGraph) = (graph.graph_backend.lightgraph,graph.graph_backend.graph_map)

function LightGraphs.all_neighbors(graph::OptiGraph,node::OptiNode)
    hyper_graph,hyper_map = graph_backend(graph)
    hypernode = hyper_map[node]
    neighbors = LightGraphs.all_neighbors(hyper_graph,hypernode)
    return [hypermap[neighbor] for neighbor in neighbors]
end

function incident_edges(graph::OptiGraph,node::OptiNode)
    hyper_graph,hyper_map = graph_backend(graph)
    hypernode = hypermap[node]
    i_edges = incident_edges(hypergraph,hypernode)
    return [hypermap[edge] for edge in i_edges]
end

function partition_list(graph::OptiGraph,membership_vector::Vector{Int64},ref_map::Dict)
    unique_parts = unique(membership_vector)  #get unique membership entries
    unique_parts = sort(unique_parts)
    nparts = length(unique_parts)             #number of partitions

    partitions = OrderedDict{Int64,Vector{OptiNode}}((k,[]) for k in unique_parts)
    for (vertex,part) in enumerate(membership_vector)
        push!(partitions[part],ref_map[vertex])
    end
    parts = collect(values(partitions))
    # return [getindex.(Ref(ref_map),parts[i] for i = 1:nparts)]
    return parts
end
@deprecate getpartitionlist partition_list

#TODO: remove this interface.  It makes more sense to just maintain the mapping and work with the actual graph structure.
#TODO: Efficient neighborhood implementation
"""
    neighborhood(graph::OptiGraph,nodes::Vector{OptiNode},distance::Int64)::Vector{OptiNode}

Return the optinodes within `distance` of the given `nodes` in the optigraph `graph`.
"""
function neighborhood(graph::OptiGraph,nodes::Vector{OptiNode},distance::Int64)
    hypergraph,hyper_map = gethypergraph(graph)
    hypernodes = [hyper_map[node] for node in nodes]
    new_nodes = neighborhood(hypergraph,hypernodes,distance)
    return [hyper_map[node] for node in new_nodes]
end

function induced_edges(graph::OptiGraph,nodes::Vector{OptiNode})
    hypergraph,hyper_map = gethypergraph(graph)
    hypernodes = [hyper_map[node] for node in nodes]
    induced = induced_edges(hypergraph,hypernodes)
    return [hyper_map[edge] for edge in induced]
end

function incident_edges(graph::OptiGraph,nodes::Vector{OptiNode})
    hypergraph,hyper_map = gethypergraph(graph)
    hypernodes = [hyper_map[node] for node in nodes]
    incident = incident_edges(hypergraph,hypernodes)
    return [hyper_map[edge] for edge in incident]
end

function identify_edges(graph::OptiGraph,node_vectors::Vector{Vector{OptiNode}})
    hypergraph,ref = gethypergraph(graph)
    hypernode_vectors = [getindex.(Ref(ref),nodes) for nodes in node_vectors]
    part_edges,cross_edges = identify_edges(hypergraph,hypernode_vectors)
    link_part_edges = [getindex.(Ref(ref),edges) for edges in part_edges]
    link_cross_edges = getindex.(Ref(ref),cross_edges)
    return link_part_edges,link_cross_edges
end

"""
    expand(graph::OptiGraph,subgraph::OptiGraph,distance::Int64)

Return a new expanded subgraph given the optigraph `graph` and an existing subgraph `subgraph`.
The returned subgraph contains the expanded neighborhood within `distance` of the given `subgraph`.
"""
function expand(graph::OptiGraph,subgraph::OptiGraph,distance::Int64)
    hypergraph,hyper_map = gethypergraph(graph)
    nodes = all_nodes(subgraph)
    hypernodes = [hyper_map[node] for node in nodes]

    new_nodes = neighborhood(hypergraph,hypernodes,distance)
    new_edges =  induced_edges(hypergraph,new_nodes)

    new_optinodes = [hyper_map[node] for node in new_nodes]
    new_optiedges = [hyper_map[edge] for edge in new_edges]

    new_subgraph = OptiGraph()
    new_subgraph.optinodes = new_optinodes
    new_subgraph.optiedges = new_optiedges

    return new_subgraph
end

function LightGraphs.induced_subgraph(graph::OptiGraph,nodes::Vector{OptiGraph})
    edges = OptiGraphs.induced_edges(graph,nodes)
    subgraph = OptiGraph()
    subgraph.optinodes = nodes
    subgraph.optiedges = edges
    return subgraph
end

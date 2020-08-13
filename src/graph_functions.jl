function LightGraphs.incidence_matrix(graph::OptiGraph)
    return sparse(graph)
end

# function adjacency_matrix(graph::HyperGraph)
# end

function LightGraphs.all_neighbors(mg::OptiGraph,node::OptiNode)
    hypergraph,hypermap = gethypergraph(mg)
    hypernode = hypermap[node]
    neighbors = LightGraphs.all_neighbors(hypergraph,hypernode)
    return [hypermap[neighbor] for neighbor in neighbors]
end

function incident_edges(mg::OptiGraph,node::OptiNode)
    hypergraph,hypermap = gethypergraph(mg)
    hypernode = hypermap[node]
    i_edges = incident_edges(hypergraph,hypernode)
    return [hypermap[edge] for edge in i_edges]
end

function getpartitionlist(graph::OptiGraph,membership_vector::Vector{Int64},ref_map::Dict)
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

#this is really just closed neighbors
function neighborhood(mg::OptiGraph,nodes::Vector{OptiNode},distance::Int64)
    hypergraph,hyper_map = gethypergraph(mg)
    hypernodes = [hyper_map[node] for node in nodes]
    new_nodes = neighborhood(hypergraph,hypernodes,distance)
    return [hyper_map[node] for node in new_nodes]
end

function induced_edges(mg::OptiGraph,nodes::Vector{OptiNode})
    hypergraph,hyper_map = gethypergraph(mg)
    hypernodes = [hyper_map[node] for node in nodes]
    induced = induced_edges(hypergraph,hypernodes)
    return [hyper_map[edge] for edge in induced]
end

function incident_edges(mg::OptiGraph,nodes::Vector{OptiNode})
    hypergraph,hyper_map = gethypergraph(mg)
    hypernodes = [hyper_map[node] for node in nodes]
    incident = incident_edges(hypergraph,hypernodes)
    return [hyper_map[edge] for edge in incident]
end

function identify_edges(mg::OptiGraph,node_vectors::Vector{Vector{OptiNode}})
    hypergraph,ref = gethypergraph(mg)
    hypernode_vectors = [getindex.(Ref(ref),nodes) for nodes in node_vectors]
    part_edges,cross_edges = identify_edges(hypergraph,hypernode_vectors)
    link_part_edges = [getindex.(Ref(ref),edges) for edges in part_edges]
    link_cross_edges = getindex.(Ref(ref),cross_edges)
    return link_part_edges,link_cross_edges
end

function expand(mg::OptiGraph,subgraph::OptiGraph,distance::Int64)
    hypergraph,hyper_map = gethypergraph(mg)
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

function LightGraphs.induced_subgraph(mg::OptiGraph,nodes::Vector{OptiGraph})
    edges = OptiGraphs.induced_edges(mg,nodes)
    subgraph = OptiGraph()
    subgraph.optinodes = nodes
    subgraph.optiedges = edges
    return subgraph
end

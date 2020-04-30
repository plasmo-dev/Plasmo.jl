function incidence_matrix(graph::ModelGraph)
    return sparse(graph)
end

# function adjacency_matrix(graph::HyperGraph)
# end

function LightGraphs.all_neighbors(mg::ModelGraph,node::ModelNode)
    hypergraph,hypermap = gethypergraph(mg)
    hypernode = hypermap[node]
    neighbors = LightGraphs.all_neighbors(hypergraph,hypernode)
    return [hypermap[neighbor] for neighbor in neighbors]
end

function incident_edges(mg::ModelGraph,node::ModelNode)
    hypergraph,hypermap = gethypergraph(mg)
    hypernode = hypermap[node]
    i_edges = incident_edges(hypergraph,hypernode)
    return [hypermap[edge] for edge in i_edges]
end

#this is really just closed neighbors
function neighborhood(mg::ModelGraph,nodes::Vector{ModelNode},distance::Int64)
    hypergraph,hyper_map = gethypergraph(mg)
    hypernodes = [hyper_map[node] for node in nodes]
    new_nodes = neighborhood(hypergraph,hypernodes,distance)
    return [hyper_map[node] for node in new_nodes]
end

function induced_edges(mg::ModelGraph,nodes::Vector{ModelNode})
    hypergraph,hyper_map = gethypergraph(mg)
    hypernodes = [hyper_map[node] for node in nodes]
    induced = induced_edges(hypergraph,hypernodes)
    return [hyper_map[edge] for edge in induced]
end

function incident_edges(mg::ModelGraph,nodes::Vector{ModelNode})
    hypergraph,hyper_map = gethypergraph(mg)
    hypernodes = [hyper_map[node] for node in nodes]
    incident = incident_edges(hypergraph,hypernodes)
    return [hyper_map[edge] for edge in incident]
end

function identify_edges(mg::ModelGraph,node_vectors::Vector{Vector{ModelNode}})
    hypergraph,ref = gethypergraph(mg)
    hypernode_vectors = [getindex.(Ref(ref),nodes) for nodes in node_vectors]
    part_edges,cross_edges = identify_edges(hypergraph,hypernode_vectors)
    link_part_edges = [getindex.(Ref(ref),edges) for edges in part_edges]
    link_cross_edges = getindex.(Ref(ref),cross_edges)
    return link_part_edges,link_cross_edges
end

function expand(mg::ModelGraph,subgraph::ModelGraph,distance::Int64)
    hypergraph,hyper_map = gethypergraph(mg)
    nodes = all_nodes(subgraph)
    hypernodes = [hyper_map[node] for node in nodes]

    new_nodes = neighborhood(hypergraph,hypernodes,distance)
    new_edges =  induced_edges(hypergraph,new_nodes)

    new_modelnodes = [hyper_map[node] for node in new_nodes]
    new_linkedges = [hyper_map[edge] for edge in new_edges]

    new_subgraph = ModelGraph()
    new_subgraph.modelnodes = new_modelnodes
    new_subgraph.linkedges = new_linkedges

    return new_subgraph
end

function LightGraphs.induced_subgraph(mg::ModelGraph,nodes::Vector{ModelNode})
    edges = ModelGraphs.induced_edges(mg,nodes)
    subgraph = ModelGraph()
    subgraph.modelnodes = nodes
    subgraph.linkedges = edges
    return subgraph
end

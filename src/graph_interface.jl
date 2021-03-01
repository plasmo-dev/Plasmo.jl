"""
    GraphBackend(graph::OptiGraph)

Create a graph backend for `graph` corresponding to a `LightGraphs` object.  A `GraphBackend` is used to do graph analysis on an optigraph
by mapping optigraph elements to lightgraph objects.
"""
struct GraphBackend
    lightgraph::LightGraphs.AbstractGraph
    graph_map::Dict #TODO: A 2 way mapping dictionary
end

#Default backend is a hypergraph backend
function GraphBackend(optigraph::OptiGraph)
    hypergraph,hypermap = hyper_graph(optigraph)
    backend = GraphBackend(hypergraph,hypermap)
end

function set_graph_backend(graph::OptiGraph,backend::GraphBackend = GraphBackend())
    graph.graph_backend = backend
end
graph_backend(graph::OptiGraph) = (graph.graph_backend)

"""
    hyper_graph(graph::OptiGraph)

Retrieve a hypergraph representation of the optigraph `graph`. Returns a [`HyperGraph`](@ref) object, as well as a dictionary
that maps hypernodes and hyperedges to the original optinodes and optiedges.
"""
function hyper_graph(graph::OptiGraph)
    hypergraph = HyperGraph()
    hyper_map = Dict()  #two-way mapping from hypergraph nodes to optinodes and link_edges

    for node in all_nodes(graph)
        hypernode = add_node!(hypergraph)
        hyper_map[hypernode] = node
        hyper_map[node] = hypernode
    end

    for edge in all_edges(graph)
        nodes = edge.nodes
        hypernodes = [hyper_map[optinode] for optinode in nodes]
        if length(hypernodes) >= 2
            hyperedge = add_hyperedge!(hypergraph,hypernodes...)
            hyper_map[hyperedge] = edge
            hyper_map[edge] = hyperedge
        end
    end

    return hypergraph,hyper_map
end

"""
    edge_hypergraph(graph::OptiGraph)

Retrieve a hypergraph representation of the optigraph `graph`. Returns a [`HyperGraph`](@ref) object, as well as a dictionary
that maps hypernodes and hyperedges to the original optinodes and optiedges.
"""
function edge_hyper_graph(graph::OptiGraph)
    hypergraph = HyperGraph()
    hyper_map = Dict()

    for edge in all_edges(graph)
        hypernode = add_node!(hypergraph)
        hyper_map[hypernode] = edge
        hyper_map[edge] = hypernode
    end

    #TODO: get nodes that connect edges


    return hypergraph,hyper_map
end


"""
    clique_graph(graph::OptiGraph)

Retrieve a standard graph representation of the optigraph `graph`. Returns a [`LightGraphs.Graph`](@ref) object, as well as a dictionary
that maps vertices and edges to the optinodes and optiedges.
"""
function clique_graph(optigraph::OptiGraph)
    graph = LightGraphs.Graph()
    graph_map = Dict()

    for optinode in all_nodes(optigraph)
        add_vertex!(graph)
        vertex = nv(graph)
        graph_map[vertex] = optinode
        graph_map[optinode] = vertex
    end

    #Optiedges
    for edge in all_edges(optigraph)
        graph_map[edge] = []
        nodes = edge.nodes
        edge_vertices = [graph_map[optinode] for optinode in nodes]
        for i = 1:length(edge_vertices)
            vertex_from = edge_vertices[i]
            other_vertices = edge_vertices[i+1:end]
            for j = 1:length(other_vertices)
                vertex_to = other_vertices[j]
                inserted = LightGraphs.add_edge!(graph,vertex_from,vertex_to)
                new_edge = LightGraphs.SimpleEdge(sort([vertex_from,vertex_to])...)
                if inserted #new simple edge was created
                    graph_map[new_edge] = edge
                    push!(graph_map[edge],new_edge)
                end
            end
        end
    end
    return graph,graph_map
end

"""
    edge_clique_graph(graph::OptiGraph)

Retrieve the line graph clique representation of the optigraph `graph`. Returns a [`LightGraphs.Graph`](@ref) object, as well as a dictionary
that maps vertices and edges to the optinodes and optiedges. The dual cliquegraph inverts nodes and edges to allow edge partitioning.
"""
function edge_clique_graph(optigraph::OptiGraph)
end


"""
    bipartite_graph(graph::OptiGraph)

Create a bipartite graph using a optigraph
"""
function bipartite_graph(graph::OptiGraph)
end

@deprecate gethypergraph hyper_graph
@deprecate getcliquegraph clique_graph


#INTERFACE FUNCTIONS
# #TODO: macro wrap for graph backend
# macro forward_graph_method(func)
#     return quote
#         function $func(graph::OptiGraph,arg)
#             backend = graph_backend(graph)
#             lightgraph,graph_map = [backend.lightgraph,backend.graph_map]
#             output = $func(lightgraph,
#         end
#     end
# end

#@forward_graph_method LightGraphs.all_neighbors

function LightGraphs.all_neighbors(graph::OptiGraph,node::OptiNode)
    backend = graph_backend(graph)
    lightgraph,graph_map = [backend.lightgraph,backend.graph_map]
    vertex = graph_map[node]
    neighbors = LightGraphs.all_neighbors(lightgraph,vertex)
    return getindex.(Ref(graph_map),neighbors)
end

function LightGraphs.induced_subgraph(graph::OptiGraph,nodes::Vector{OptiGraph})
    edges = induced_edges(graph,nodes)
    #TODO: Setup other attributes needed for an optigraph (e.g. node_idx_map,edge_idx_map)
    subgraph = OptiGraph()
    subgraph.optinodes = nodes
    subgraph.optiedges = edges
    return subgraph
end

function incident_edges(graph::OptiGraph,node::OptiNode)
    backend = graph_backend(graph)
    lightgraph,graph_map = [backend.lightgraph,backend.graph_map]
    vertex = graph_map[node]
    inc_edges = incident_edges(lightgraph,vertex)
    return getindex.(Ref(graph,map,inc_edges))
end

#Incident edges to a set of optinodes
function incident_edges(graph::OptiGraph,nodes::Vector{OptiNode})
    hypergraph,hyper_map = gethypergraph(graph)
    hypernodes = [hyper_map[node] for node in nodes]
    incident = incident_edges(hypergraph,hypernodes)
    return [hyper_map[edge] for edge in incident]
end

#TODO: don't need ordered dict for this
function partition_list(graph::OptiGraph,membership_vector::Vector{Int64})
    backend = graph_backend(graph)
    lightgraph,graph_map = [backend.lightgraph,backend.graph_map]
    partitions = partition_list(lightgraph,memebership_vector)
    return [getindex.(Ref(graph_map),partitions[i] for i = 1:length(partitions))]
end
@deprecate getpartitionlist partition_list

#TODO: Efficient neighborhood implementation
"""
    neighborhood(graph::OptiGraph,nodes::Vector{OptiNode},distance::Int64)::Vector{OptiNode}

Return the optinodes within `distance` of the given `nodes` in the optigraph `graph`.
"""
function neighborhood(graph::OptiGraph,nodes::Vector{OptiNode},distance::Int64)
    backend = graph_backend(graph)
    lightgraph,graph_map = [backend.lightgraph,backend.graph_map]
    vertices = [graph_map[node] for node in nodes]
    new_nodes = neighborhood(lightgraph,vertices,distance)
    return [graph_map[node] for node in new_nodes]
end

function induced_edges(graph::OptiGraph,nodes::Vector{OptiNode})
    hypergraph,hyper_map = gethypergraph(graph)
    hypernodes = [hyper_map[node] for node in nodes]
    induced = induced_edges(hypergraph,hypernodes)
    return [hyper_map[edge] for edge in induced]
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


# LightGraphs.incidence_matrix(graph::OptiGraph) = sparse(graph)
# function adjacency_matrix(graph::HyperGraph)
# end


# function partition_list(graph::OptiGraph,membership_vector::Vector{Int64},ref_map::Dict)
#     unique_parts = unique(membership_vector)  #get unique membership entries
#     unique_parts = sort(unique_parts)
#     nparts = length(unique_parts)             #number of partitions
#
#     partitions = OrderedDict{Int64,Vector{OptiNode}}((k,[]) for k in unique_parts)
#     for (vertex,part) in enumerate(membership_vector)
#         push!(partitions[part],ref_map[vertex])
#     end
#     parts = collect(values(partitions))
#     # return [getindex.(Ref(ref_map),parts[i] for i = 1:nparts)]
#     return parts
# end

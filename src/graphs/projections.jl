#ProjectionMap maps from an expanded (projected) hypergraph back to the original hypergraph nodes and hyperedges
struct ProjectionMap
    node_map::Dict{Int64,HyperNode}
    edge_map::Dict{LightGraphs.AbstractEdge,Vector{HyperEdge}}
end
ProjectionMap() = ProjectionMap(Dict{Int64,HyperNode}(),Dict{LightGraphs.AbstractEdge,HyperEdge}())

function Base.getindex(projection_map::ProjectionMap,node_index::Int64)
    return projection_map.node_map[node_index]
end
function Base.getindex(projection_map::ProjectionMap, edge_index::LightGraphs.AbstractEdge)
    return projection_map.edge_map[edge_index]
end
Base.broadcastable(projection_map::ProjectionMap) = Ref(projection_map)


function Base.setindex!(projection_map::ProjectionMap,hyper_node::HyperNode,node_index::Int64)
    projection_map.node_map[node_index] = hyper_node
end

function Base.setindex!(projection_map::ProjectionMap, hyper_edges::Vector{HyperEdge},edge_index::LightGraphs.AbstractEdge)
    projection_map.edge_map[edge_index] = hyper_edges
end

function Base.merge!(proj_map1::ProjectionMap,proj_map2::ProjectionMap)
    for (k,v) in proj_map2.node_map
        proj_map1.node_map_map[k] = v
    end
    for (k,v) in proj_map2.edge_map
        proj_map1.edge_map[k] = v
    end
end

#clique expansion
#TODO: Just return a lightgraph undirected graph
function clique_expansion(hypergraph::HyperGraph)

    #graph = CliqueExpandedGraph()
    graph = LightGraphs.Graph()
    projection_map = ProjectionMap()

    #Nodes
    for node in getnodes(hypergraph)
        add_vertex!(graph)
        i = nv(graph)
        projection_map[i]= node
    end

    #HyperEdges
    for hyperedge in gethyperedges(hypergraph)
        edge_vertices = vertices(hyperedge)
        for i = 1:length(edge_vertices)
            vertex_from = getindex(hypergraph,edge_vertices[i])
            other_vertices = edge_vertices[i+1:end]
            for j = 1:length(other_vertices)
                vertex_to = getindex(hypergraph,other_vertices[j])
                inserted = LightGraphs.add_edge!(graph,vertex_from,vertex_to)
                new_edge = LightGraphs.SimpleEdge(sort([vertex_from,vertex_to])...)
                if inserted #new simple edge was created
                    projection_map.edge_map[new_edge] = [hyperedge]
                elseif !(hyperedge in values(projection_map.edge_map[new_edge]))
                    push!(projection_map.edge_map[new_edge],hyperedge)
                else #nothing to do
                    continue
                end
            end
        end
    end
    return graph,projection_map
end

function star_expansion(graph::HyperGraph)
    new_graph = BipartiteGraph()
    projection_map = Dict()
    return new_graph,projection_map
end


# function dual_hypergraph(hypergraph::HyperGraph)
# end
#
# function dual_clique_expansion(hypergraph::HyperGraph)
# end

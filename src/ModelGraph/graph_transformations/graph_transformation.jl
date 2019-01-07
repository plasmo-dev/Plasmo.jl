#Functions that do graph transformations to facilitate different decomposition algorithms

#Convert ModelGraph ==> ModelTree
#NOTE: Could use a spanning tree?
function getmodeltree(graph::ModelGraph;root_node = nothing)
    #1.) If no root_node, lift all the link constraints into a root node
    #if root_node == nothing


    #2.) If there is a root node, create the tree by recursively going out
    #3.) Lift hyper-constraints into root node
end

# IDEA: Use a Unipartite graph to do partitioning
#Convert Hypergraph ==> Unipartite Graph
function getunipartitegraph(graph::ModelGraph)
    ugraph = UnipartiteGraph()

    #Add the model nodes to the Unipartite graph
    for node in getnodes(graph)
        idx = getindex(graph,node)
        new_node = create_node(ugraph)
        n_vars = length(getmodel(node).colVal)
        add_node!(ugraph,new_node,index = idx)
        new_index = getindex(ugraph,new_node)
        ugraph.v_weights[new_index] = n_vars  #node weights are number of variables
    end

    #Add the edges between nodes
    #TODO Handle hierachical structures
    for edge in getedges(graph)
        hyperedge = getindex(graph,edge)
        vertices = hyperedge.vertices
        for i = 1:length(vertices)
            node_from = getnode(ugraph,vertices[i])
            other_vertices = vertices[i+1:end]
            for j = 1:length(other_vertices)
                node_to = getnode(ugraph,other_vertices[j])
                new_edge = add_edge!(ugraph,node_from,node_to)
                new_index = getindex(ugraph,new_edge)
                if !haskey(ugraph.e_weights,new_index)
                    ugraph.e_weights[new_index] = 1
                else
                    ugraph.e_weights[new_index] += length(edge.linkconrefs)  #edge weights are number of link constraints
                end
            end
        end
    end
    return ugraph
end

#Convert Hypergraph ==> Bipartite Graph
function getbipartitegraph(graph::ModelGraph)
    bgraph = BipartiteGraph()

    #model nodes
    for node in getnodes(graph)
        idx = getindex(graph,node)
        new_node = create_node(bgraph)
        add_node!(bgraph,new_node,index = idx)  #keep the same indices
        push!(bgraph.part1,idx)
    end

    #hyper edges
    for edge in getedges(graph)
        hyperedge = getindex(graph,edge)
        vertices = hyperedge.vertices
        constraint_node = add_node!(bgraph)
        push!(bgraph.part2,getindex(bgraph,constraint_node))
        #connect this "node" to the other nodes
        for vertex in vertices
            model_node = getnode(bgraph,vertex)
            add_edge!(bgraph,constraint_node,model_node)
        end
    end
    return bgraph
end

#Convert JuMP Model ==> Bipartite Graph
function getbipartitegraph(model::JuMP.Model)

end

#Convert JuMP Model ==> Unipartite Graph
function getunipartitegraph(graph::JuMP.Model)

end

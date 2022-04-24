#Structure attributes for an OptiGraph
@enum GraphStructure begin
    GRAPH = 1                   #No subgraphs
    TREE = 2                    #One subgraph w/ (possibly) parent node
    LINKED_TREE = 3             #One subgraph with linked subgraph nodes
    RECURSIVE_GRAPH = 4         #Graph with subgraphs.  No local nodes in graph.
    RECURSIVE_TREE = 5          #Graph with subgraphs.  Graph can have local nodes
    RECURSIVE_LINKED_TREE = 6
end

"""
    graph_structure(graph::OptiGraph)
Return a value corresponding to the hierarchical structure of an optigraph.  Values correspond to:
GRAPH = 1
TREE = 2
LINKED_TREE = 3
RECURSIVE_GRAPH = 4
RECURSIVE_TREE = 5
RECURSIVE_LINKED_TREE = 6
"""
function graph_structure(graph::OptiGraph)
    if !(has_subgraphs(graph))
        return GRAPH
    end

    if num_subgraphs(graph) == 1
        if num_edges(graph.subgraphs[1]) == 0
            return TREE
        else
            return LINKED_TREE
        end
    end

    if num_subgraphs(graph) > 1
        if num_nodes(graph) == 0
            return RECURSIVE_GRAPH
        else
            if _links_subgraphs(graph)
                return RECURSIVE_LINKED_TREE
            else
                return RECURSIVE_TREE
            end
        end
    end
end

#recurisely calculate depth
function graph_depth(graph::OptiGraph)
    depth = 0
    if has_subgraphs(graph)
        depth += 1
        depth += _subgraph_depth(subgraphs(graph))
    end
    return depth
end

#recursively check whether any edges link subgraphs
function _links_subgraphs(graph::OptiGraph)
    return_val = false
    if num_subgraphs(graph) > 1
        for subgraph in subgraphs(graph)
            sub_incident_edges = incident_edges(graph, optinodes(subgraph))
            hier_edges = hierarchical_edges(graph)
            if length(setdiff(sub_incident_edges,hier_edges)) > 0
                return_val = true
                break
            else
                return_val = _links_subgraphs(subgraph)
            end
        end
    end
    return return_val
end

#recursively check subgraph depth
function _subgraph_depth(subgraphs::Vector{OptiGraph})
    depth = 0
    if any((g) -> has_subgraphs(g),subgraphs)
        depth += 1
        for sub in subgraphs
            depth += _subgraph_depth(getsubgraphs(sub))
        end
    end
    return depth
end

#TODO:
#Other model traits we can communicate to solvers:
#NLLinkConstraints
#Integer variables in subgraphs
#Incident hyper-edge (a hyper-edge that connects first stage to multiple 2nd stage nodes)

#TODO:
#Aggregate to Tree, Graph, etc...

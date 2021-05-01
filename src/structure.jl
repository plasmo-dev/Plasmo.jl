#Structure attributes for an OptiGraph
@enum GraphStructure begin
    GRAPH = 1                   #No subgraphs
    TREE = 2                    #One subgraph w/ (possibly) parent node
    LINKED_TREE = 3             #One subgraph with linked subgraph nodes
    RECURSIVE_GRAPH = 4         #
    RECURSIVE_TREE = 5
    RECURSIVE_LINKED_TREE = 6
end

#Inspect optigraph and figure out the structure
#TODO: RECURSIVE_LINKED_TREE
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
            return RECURSIVE_TREE
        end
    end

end

function recursive_depth(graph::OptiGraph)
    depth = 0
    if has_subgraphs(graph)
    end

    return depth
end

# function _links_subgraphs(graph::OptiGraph)
#     if num_subgraphs(graph) > 1
#         for subgraph in getsubgraphs(graph)
#             for edge in getedges(graph)
#
#             #if !any((node) -> node in getnodes(graph),getnodes(edge))
#
#                 #if !all((node) -> node in getnodes(graph),getnodes(edge))
#                     return true
#                 end
#             end
#         else
#             for subgraph in getsubgraphs(graph)
#
#         end
#         return false
# end

"""
    aggregate_backends!(graph::OptiGraph)

Aggregate the moi backends from each subgraph within `graph` to create a single backend.
"""
function aggregate_backends!(graph::OptiGraph)
    for subgraph in get_subgraphs(graph)
        _aggregate_subgraph_nodes!(subgraph)
        _aggregate_subgraph_edges!(subgraph)
    end
end

function _aggregate_subgraph_nodes!(graph::OptiGraph)
    for node in all_nodes(graph)
        _append_node_to_backend!(graph, node)
    end
end

function _append_node_to_backend!(graph::OptiGraph, node::OptiNode)
    src = graph_backend(node)
    dest = graph_backend(graph)

    node_variables = all_variables(node)
    vis_src = graph_index.(node_variables) # variable indices on src graph

    # TODO: get variable constraints specifically for this node
    # variable_constraints = Any[
    #     MOI.get(src, MOI.ListOfConstraintIndices{F,S}()) for
    #     (F, S) in MOI.get(src, MOI.ListOfConstraintTypesPresent()) if
    #     MOIU._is_variable_function(F)
    # ]
    
    index_map = MOIU.IndexMap()

    # copy node variables
    _copy_node_variables(dest, index_map, node_variables)
    # println(index_map)

    # copy variable attributes (e.g. VariablePrimalStart(), VariableName())
    MOI.Utilities.pass_attributes(dest.moi_backend, src.moi_backend, index_map, vis_src)

    _copy_variable_node_constraints(dest.moi_backend, src.moi_backend, index_map, vis_src)

    # TODO: constraints
    # MOI.Utilities._pass_constraints(dest.moi_backend, src.moi_backend, index_map, constraints_not_added)
end

# TODO: MOI functions to get variables and constraints on nodes

function _copy_node_variables(
    dest::GraphMOIBackend, 
    index_map::MOIU.IndexMap,
    node_variables::Vector{NodeVariableRef}
)
    # map existing variables in index_map
    existing_vars = intersect(node_variables, keys(dest.node_to_graph_map.var_map))
    for var in existing_vars
        src_graph_index = graph_index(var)
        dest_graph_index = dest.node_to_graph_map[var]
        index_map[src_graph_index] = dest_graph_index
    end

    # create and add new variables
    vars_to_add = setdiff(node_variables, keys(dest.node_to_graph_map.var_map))
    for var in vars_to_add
        src_graph_index = graph_index(var)
        dest_graph_index = _add_variable_to_backend(dest, var)
        index_map[src_graph_index] = dest_graph_index
    end
    return
end

function _copy_variable_node_constraints(dest::GraphMOIBackend, src::OptiNode)
    for cis in variable_constraints
        _copy_constraints(dest, src, index_map, cis)
    end
end

function _copy_nonvariable_node_constraints(
    dest::MOI.ModelLike,
    src::MOI.ModelLike,
    index_map::MOI.Utilities.IndexMap
)

    all_constraint_types = MOI.get(src, MOI.ListOfConstraintTypesPresent())
    nonvariable_constraint_types = filter(all_constraint_types) do (F, S)
        return !_is_variable_function(F)
    end
    
    pass_nonvariable_constraints(
        dest,
        src,
        index_map,
        nonvariable_constraint_types,
    )
    
    # pass constraint attributes
    for (F, S) in all_constraint_types
        pass_attributes(
            dest,
            src,
            index_map,
            MOI.get(src, MOI.ListOfConstraintIndices{F,S}()),
        )
    end
    
    return
end




# function MOIU.pass_attributes(
#     dest::GraphMOIBackend, 
#     src::GraphMOIBackend,
#     index_map::MOIU.IndexMap
# )
#     MOIU.pass_attributes(dest.moi_backend, src.moi_backend, index_map)
# end

# function MOI.Utilities.pass_nonvariable_constraints(
#     dest::GraphMOIBackend,
#     src::OptiNode,
#     index_map::MOIU.IndexMap,
#     constraint_types,
# )
#   for (F, S) in constraint_types
#       cis_src = MOI.get(src, MOI.ListOfConstraintIndices{F,S}())
#       _copy_constraints(dest, src, index_map, cis_src)
#     end

#     return
# end

# function pass_nonvariable_constraints_fallback(
#     dest::MOI.ModelLike,
#     src::MOI.ModelLike,
#     index_map::IndexMap,
#     constraint_types,
# )
#     for (F, S) in constraint_types
#         cis_src = MOI.get(src, MOI.ListOfConstraintIndices{F,S}())
#         _copy_constraints(dest, src, index_map, cis_src)
#     end
#     return
# end

# function _copy_constraints(
#     dest::MOI.ModelLike,
#     src::MOI.ModelLike,
#     index_map,
#     index_map_FS,
#     cis_src::Vector{<:MOI.ConstraintIndex},
# )
#     for ci in cis_src
#         f = MOI.get(src, MOI.ConstraintFunction(), ci)
#         s = MOI.get(src, MOI.ConstraintSet(), ci)
#         index_map_FS[ci] =
#             MOI.add_constraint(dest, map_indices(index_map, f), s)
#     end
#     return
# end

# function _copy_constraints(
#     dest::MOI.ModelLike,
#     src::MOI.ModelLike,
#     index_map,
#     cis_src::Vector{MOI.ConstraintIndex{F,S}},
# ) where {F,S}
#     return _copy_constraints(dest, src, index_map, index_map[F, S], cis_src)
# end
























### Helpful utilities

# """
#     append_to_backend!(dest::MOI.ModelLike, src::MOI.ModelLike)

# Copy the underylying model from `src` into `dest`, but ignore attributes
# such as objective function and objective sense
# """
# function append_to_backend!(dest::MOI.ModelLike, src::MOI.ModelLike)
#     vis_src = MOI.get(src, MOI.ListOfVariableIndices())   #returns vector of MOI.VariableIndex
#     index_map = MOIU.IndexMap()


#     # has_nlp = MOI.NLPBlock() in MOI.get(src, MOI.ListOfModelAttributesSet())
#     # constraints_not_added = if has_nlp
#     constraints_not_added = Any[
#         MOI.get(src, MOI.ListOfConstraintIndices{F,S}()) for
#         (F, S) in MOI.get(src, MOI.ListOfConstraintTypesPresent()) if
#         MOIU._is_variable_function(F)
#     ]
#     # else
#     #     Any[
#     #         MOIU._try_constrain_variables_on_creation(dest, src, index_map, S)
#     #         for S in MOIU.sorted_variable_sets_by_cost(dest, src)
#     #     ]
#     # end

#     # Copy free variables into graph optimizer
#     MOI.Utilities._copy_free_variables(dest, index_map, vis_src)

#     # Copy variable attributes (e.g. name, and VariablePrimalStart())
#     MOI.Utilities.pass_attributes(dest, src, index_map, vis_src)

#     # Normally this copies ObjectiveSense() and ObjectiveFunction(), but we don't want to do that here
#     # MOI.Utilities.pass_attributes(dest, src, idxmap)

#     MOI.Utilities._pass_constraints(dest, src, index_map, constraints_not_added)

#     return index_map    #return an idxmap for each source model
# end
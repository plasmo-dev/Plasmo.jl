"""
	aggregate_backends!(graph::OptiGraph)

Aggregate the moi backends from each subgraph within `graph` to create a single backend.
"""
function aggregate_backends!(graph::OptiGraph)
	dest = JuMP.backend(graph)

end

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
#     #MOI.Utilities.pass_attributes(dest, src, idxmap)

#     MOI.Utilities._pass_constraints(dest, src, index_map, constraints_not_added)

#     return index_map    #return an idxmap for each source model
# end
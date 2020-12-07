backend(graph::OptiGraph) = graph.moi_backend

#IDEA:
# OptiGraph NLP Evaluator
# Look at JuMP NLP Evaluator for ideas here. We could use all of the Optinodes to throw together a quick OptiGraph NLPEvaluator

#Copy a model backend without emptying the previous model.  Increment variable indices as necessary
function default_copy_to(dest::MOI.ModelLike, src::MOI.ModelLike,
                         copy_names::Bool,
                         filter_constraints::Union{Nothing, Function}=nothing)
    #MOI.empty!(dest)


    vis_src = MOI.get(src, MOI.ListOfVariableIndices())

    #idxmap = MOI.index_map_for_variable_indices(vis_src)
    idxmap = MOI.Utilities.IndexMap()

    # The `NLPBlock` assumes that the order of variables does not change (#849)
    if MOI.NLPBlock() in MOI.get(src, MOI.ListOfModelAttributesSet())
        constraint_types = MOI.get(src, MOI.ListOfConstraints())
        single_variable_types = [S for (F, S) in constraint_types
                                 if F == MOI.SingleVariable]
        vector_of_variables_types = [S for (F, S) in constraint_types
                                     if F == MOI.VectorOfVariables]
        vector_of_variables_not_added = [
            MOI.get(src, MOI.ListOfConstraintIndices{MOI.VectorOfVariables, S}())
            for S in vector_of_variables_types
        ]
        single_variable_not_added = [
            MOI.get(src, MOI.ListOfConstraintIndices{MOI.SingleVariable, S}())
            for S in single_variable_types
        ]
    else
        vector_of_variables_types, _, vector_of_variables_not_added,
        single_variable_types, _, single_variable_not_added = try_constrain_variables_on_creation(
            dest, src, idxmap, MOI.add_constrained_variables, MOI.add_constrained_variable
        )
    end


    #TODO: look into these functions
    copy_free_variables(dest, idxmap, vis_src, MOI.add_variables)

    # Copy variable attributes
    pass_attributes(dest, src, copy_names, idxmap, vis_src)

    # Copy model attributes
    pass_attributes(dest, src, copy_names, idxmap)

    # Copy constraints
    pass_constraints(dest, src, copy_names, idxmap,
                     single_variable_types, single_variable_not_added,
                     vector_of_variables_types, vector_of_variables_not_added,
                     filter_constraints=filter_constraints)

    return idxmap
end

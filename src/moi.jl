JuMP.backend(graph::OptiGraph) = graph.moi_backend
JuMP.backend(node::OptiNode) = JuMP.backend(getmodel(node))

#An optinode can be solved just like a JuMP model, but sometimes we just want to store a value using an underlying optimizer
mutable struct NodeOptimizer <: MOI.AbstractOptimizer
    caching_optimizer::MOIU.CachingOptimizer
    var_values::OrderedDict{MOI.VariableIndex,Float64}  #variable values #{MOI.VariableIndex => Value}
    var_duals::OrderedDict{MOI.ConstraintIndex,Float64}
end

function NodeOptimizer()
    caching_mode::MOIU.CachingOptimizerMode=MOIU.AUTOMATIC
    universal_fallback = MOIU.UniversalFallback(MOIU.Model{Float64}())
    caching_opt = MOIU.CachingOptimizer(universal_fallback,caching_mode)
    return NodeOptimizer(caching_opt,nothing,nothing)
end

NodeOptimizer(caching_opt::MOIU.CachingOptimizer) = NodeOptimizer(caching_opt,nothing,nothing)

#How many functions do we need to define here?
function MOI.get(optimizer::NodeOptimizer, attr::Union{MOI.AbstractConstraintAttribute, MOI.AbstractModelAttribute, MOI.AbstractOptimizerAttribute, MOI.AbstractVariableAttribute})
    return MOI.get(optimizer.caching_optimizer,attr)
end

#Get single variable index
function MOI.get(optimizer::NodeOptimizer, attr::MOI.VariablePrimal, idx::MOI.VariableIndex)
    return optimizer.var_values[idx]
end

#Get vector of values
function MOI.get(optimizer::NodeOptimizer, attr::MOI.VariablePrimal, idx::Vector{MOI.VariableIndex})
    return getindex.(Ref(optimizer.var_values),idx)
end

# I would like to do this, but it says it's ambiguous
# MOI.get(model::NodeOptimizer, args...) = MOI.get(model.caching_optimizer,args...)


#Now we just define get for the node

#MOI.get(node_optimizer,MOI.VariablePrimal,idx) = node_optimizer.values[idx]

#IDEA for nonlinear copy:
# Create an OptiGraph NLP Evaluator
# Look at JuMP NLP Evaluator for ideas here. We could use all of the Optinodes to throw together a quick OptiGraph NLPEvaluator
# Look at MadNLP.jl for an example of an NLP evaluator that uses Plasmo.jl

#IDEA here: Copy a moi backend without emptying the previous model.  We then Increment variable and constraint indices as necessary.
#Then add linking constraints in a separate function.
function append_to_backend(dest::MOI.ModelLike, src::MOI.ModelLike, copy_names::Bool,filter_constraints::Union{Nothing, Function}=nothing)

    #Normally, the destination model is emptied out
    #variable indices of src model
    vis_src = MOI.get(src, MOI.ListOfVariableIndices())   #returns vector of MOI.VariableIndex
    idxmap = MOI.Utilities.index_map_for_variable_indices(vis_src)

    #possibly need to increment dest indices
    # vis_dest = MOI.get(dest,MOI.ListOfVariableIndices())

    # copy_names = true
    # filter_constraints = nothing


    #The standard default_copy_to doesn't really work here since we need to increment variable indices on new src models
    # The `NLPBlock` assumes that the order of variables does not change (#849)
    if MOI.NLPBlock() in MOI.get(src, MOI.ListOfModelAttributesSet())
        constraint_types = MOI.get(src, MOI.ListOfConstraints())

        single_variable_types = [S for (F, S) in constraint_types if F == MOI.SingleVariable]
        vector_of_variables_types = [S for (F, S) in constraint_types if F == MOI.VectorOfVariables]

        vector_of_variables_not_added = [MOI.get(src, MOI.ListOfConstraintIndices{MOI.VectorOfVariables, S}()) for S in vector_of_variables_types]
        single_variable_not_added = [MOI.get(src, MOI.ListOfConstraintIndices{MOI.SingleVariable, S}()) for S in single_variable_types]

    else #this sets up idxmap
        #this collects the variable set types that destination model supports
        vector_of_variables_types, _, vector_of_variables_not_added,
        single_variable_types, _, single_variable_not_added =
        MOI.Utilities.try_constrain_variables_on_creation(dest, src, idxmap, MOI.add_constrained_variables, MOI.add_constrained_variable)
    end


    #I think these are not constrained variables
    MOI.Utilities.copy_free_variables(dest, idxmap, vis_src, MOI.add_variables)

    # Copy variable attributes
    MOI.Utilities.pass_attributes(dest, src, copy_names, idxmap, vis_src)

    # Normally, this copies the objective function, but we will set that with another function
    # This would just override the objective each iteration
    # MOI.Utilities.pass_attributes(dest, src, copy_names, idxmap)

    # Copy constraints
    MOI.Utilities.pass_constraints(dest, src, copy_names, idxmap,
                     single_variable_types, single_variable_not_added,
                     vector_of_variables_types, vector_of_variables_not_added,
                     filter_constraints=filter_constraints)

    return idxmap    #return an idxmap for each optinode
end



function set_sum_of_objectives(dest,backends)
    #objective function
    #check for nonlinear objective
    #TODO: sum up the objective functions
    # MOI.set(model, MOI.ObjectiveSense(), MIN_SENSE)
    #
    # #Need to use idxmaps
    # MOI.set(dest,
    #     MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(),
    #     MOI.ScalarAffineFunction(
    #         MOI.ScalarAffineTerm.([5.0, -2.3], [x[1], x[2]]), 1.0),
    #     )
end

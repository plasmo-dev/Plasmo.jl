abstract type AbstractNodeOptimizer <: MOI.AbstractOptimizer end

#An optinode can be solved just like a JuMP model, but sometimes we just want to store a solution on it
# mutable struct NodeOptimizer <: AbstractNodeOptimizer
#     optimizer::MOI.ModelLike # optimizer::MOIU.CachingOptimizer
#     primals::OrderedDict#{MOI.VariableIndex,Float64}
#     duals::OrderedDict#{MOI.ConstraintIndex,Float64}
#     status::MOI.TerminationStatusCode
#
#
#     idx_map::MOIU.IndexMap#{node => graph}
#     nl_idx_map::OrderedDict#{node => graph}
#
#     #Multiple graph solutions are possible.  OptiGraphs and OptiNodes have unique symbols
#     id::Symbol
#     idx_maps::Dict{Symbol,OrderedDict}
#     nl_idx_maps::Dict{Symbol,OrderedDict}
#     last_solution_symbol::Union{Nothing,Symbol}
# end
#Multiple graph solutions are possible.  OptiGraphs and OptiNodes have unique symbols
mutable struct NodeOptimizer <: AbstractNodeOptimizer
    optimizer::MOI.ModelLike # optimizer::MOIU.CachingOptimizer
    id::Symbol
    primals::DefaultDict{Symbol,OrderedDict{MOI.VariableIndex,Float64}}
    duals::DefaultDict{Symbol,OrderedDict{MOI.ConstraintIndex,Float64}}
    status::MOI.TerminationStatusCode

    idx_maps::DefaultDict{Symbol,MOIU.IndexMap} #{node => graph}
    nl_idx_maps::DefaultDict{Symbol,OrderedDict} #{node => graph}
    last_solution_id::Symbol
end

function NodeOptimizer(caching_opt::MOIU.CachingOptimizer,id::Symbol)
    return NodeOptimizer(
    caching_opt,
    id,
    DefaultDict{Symbol,OrderedDict{MOI.VariableIndex,Float64}}(OrderedDict{MOI.VariableIndex,Float64}()),
    DefaultDict{Symbol,OrderedDict{MOI.ConstraintIndex,Float64}}(OrderedDict{MOI.ConstraintIndex,Float64}()),
    MOI.OPTIMIZE_NOT_CALLED,
    DefaultDict{Symbol,MOIU.IndexMap}(MOIU.IndexMap()),
    DefaultDict{Symbol,OrderedDict}(OrderedDict()),
    id)
end

#Forward methods
MOI.add_variable(node_optimizer::AbstractNodeOptimizer) = MOI.add_variable(node_optimizer.optimizer)
MOI.add_constraint(node_optimizer::AbstractNodeOptimizer,func::MOI.AbstractFunction,set::MOI.AbstractSet) = MOI.add_constraint(node_optimizer.optimizer,func,set)
MOI.get(optimizer::AbstractNodeOptimizer,attr::MOI.AnyAttribute) = MOI.get(optimizer.optimizer,attr)
MOI.get(optimizer::AbstractNodeOptimizer,attr::MOI.AnyAttribute,idx) = MOI.get(optimizer.optimizer,attr,idx)
MOI.get(optimizer::AbstractNodeOptimizer,attr::MOI.AnyAttribute,idxs::Array{T,1} where T) = MOI.get(optimizer.optimizer,attr,idxs)

#NOTE: MOI.AnyAttribute = Union{MOI.AbstractConstraintAttribute, MOI.AbstractModelAttribute, MOI.AbstractOptimizerAttribute, MOI.AbstractVariableAttribute}
MOI.set(optimizer::AbstractNodeOptimizer,attr::MOI.AnyAttribute,args...) = MOI.set(optimizer.optimizer,attr,args...)

MOI.supports_constraint(optimizer::AbstractNodeOptimizer,func::Type{T}
    where T<:MathOptInterface.AbstractFunction, set::Type{S}
    where S <: MathOptInterface.AbstractSet) = MOI.supports_constraint(optimizer.optimizer,func,set)

MOI.supports(optimizer::AbstractNodeOptimizer, attr::Union{MOI.AbstractModelAttribute, MOI.AbstractOptimizerAttribute}) = MOI.supports(optimizer.optimizer,attr)
MOIU.reset_optimizer(optimizer::AbstractNodeOptimizer,args...) = MOIU.reset_optimizer(optimizer.optimizer,args...)

#Optimize the underlying optimizer and store the result in the node optimizer
function MOI.optimize!(optimizer::AbstractNodeOptimizer)
    MOI.optimize!(optimizer.optimizer)
    vars = MOI.get(optimizer,MOI.ListOfVariableIndices())
    cons = MOI.ConstraintIndex[]
    con_list = MOI.get(optimizer,MOI.ListOfConstraints())
    for FS in con_list
        F = FS[1]
        S = FS[2]
        con = MOI.get(optimizer,MOI.ListOfConstraintIndices{F,S}())
        append!(cons,con)
    end
    primals = OrderedDict(zip(vars,MOI.get(optimizer.optimizer,MOI.VariablePrimal(),vars)))
    duals = OrderedDict(zip(cons,MOI.get(optimizer.optimizer,MOI.ConstraintDual(),cons)))

    # optimizer.primals = primals
    # optimizer.duals = duals
    id = optimizer.id
    optimizer.primals[id] = primals
    optimizer.duals[id] = duals
end

MOIU.state(optimizer::AbstractNodeOptimizer) = MOIU.state(optimizer.optimizer)

#Get single variable index
function MOI.get(optimizer::NodeOptimizer, attr::MOI.VariablePrimal, idx::MOI.VariableIndex)
    return optimizer.primals[optimizer.last_solution_id][idx]
end

function MOI.get(optimizer::NodeOptimizer, attr::MOI.ConstraintDual, idx::MOI.ConstraintIndex)
    return optimizer.duals[optimizer.last_solution_id][idx]
end

#Get vector of primal values
function MOI.get(optimizer::NodeOptimizer, attr::MOI.VariablePrimal, idx::Vector{MOI.VariableIndex})
    return getindex.(Ref(optimizer.primals[optimizer.last_solution_id]),idx)
end

#Need to set a termination status for a node optimizer.  This is what JuMP checks for.
function MOI.get(optimizer::NodeOptimizer, attr::MOI.TerminationStatus)
    return MOI.TerminationStatusCode(1) #Currently set to Optimal if a node has a solution
end

#IDEA: Copy multiple moi backends without emptying the destination model.
function append_to_backend!(dest::MOI.ModelLike, src::MOI.ModelLike, copy_names::Bool;filter_constraints::Union{Nothing, Function}=nothing)

    vis_src = MOI.get(src, MOI.ListOfVariableIndices())   #returns vector of MOI.VariableIndex
    idxmap = MOI.Utilities.index_map_for_variable_indices(vis_src)

    # The `NLPBlock` assumes that the order of variables does not change (#849)
    if MOI.NLPBlock() in MOI.get(src, MOI.ListOfModelAttributesSet())
        constraint_types = MOI.get(src, MOI.ListOfConstraints())

        single_variable_types = [S for (F, S) in constraint_types if F == MOI.SingleVariable]
        vector_of_variables_types = [S for (F, S) in constraint_types if F == MOI.VectorOfVariables]

        vector_of_variables_not_added = [MOI.get(src, MOI.ListOfConstraintIndices{MOI.VectorOfVariables, S}()) for S in vector_of_variables_types]
        single_variable_not_added = [MOI.get(src, MOI.ListOfConstraintIndices{MOI.SingleVariable, S}()) for S in single_variable_types]
    else
        #this collects the variable set types that the destination model supports
        vector_of_variables_types, _, vector_of_variables_not_added,
        single_variable_types, _, single_variable_not_added =
        MOI.Utilities.try_constrain_variables_on_creation(dest, src, idxmap, MOI.add_constrained_variables, MOI.add_constrained_variable)
    end


    #Copy free variables
    MOI.Utilities.copy_free_variables(dest, idxmap, vis_src, MOI.add_variables)

    # Copy variable attributes
    MOI.Utilities.pass_attributes(dest, src, copy_names, idxmap, vis_src)

    # Normally, this copies the objective function, but we don't want to do that here
    # MOI.Utilities.pass_attributes(dest, src, copy_names, idxmap)

    # Copy constraints
    MOI.Utilities.pass_constraints(dest, src, copy_names, idxmap,
                     single_variable_types, single_variable_not_added,
                     vector_of_variables_types, vector_of_variables_not_added,
                     filter_constraints=filter_constraints)

    return idxmap    #return an idxmap for each source model
end


#NOTE: TODO: just set objective function from optigraph
##########################################################
function _swap_indices!(obj::MOI.ScalarAffineFunction,idxmap::MOIU.IndexMap)
    terms = obj.terms
    for i = 1:length(terms)
        coeff = terms[i].coefficient
        var_idx = terms[i].variable_index
        terms[i] = MOI.ScalarAffineTerm{Float64}(coeff,idxmap[var_idx])
    end
end

function _swap_indices!(obj::MOI.ScalarQuadraticFunction,idxmap::MOIU.IndexMap)
    quad_terms = obj.quadratic_terms
    for i = 1:length(quad_terms)
        coeff = quad_terms[i].coefficient
        var_idx1 = quad_terms[i].variable_index_1
        var_idx2 = quad_terms[i].variable_index_2
        quad_terms[i] = MOI.ScalarQuadraticTerm{Float64}(coeff,idxmap[var_idx1],idxmap[var_idx2])
    end
    aff_terms = obj.affine_terms
    for i = 1:length(aff_terms)
        coeff = aff_terms[i].coefficient
        var_idx = aff_terms[i].variable_index
        terms[i] = MOI.ScalarAffineTerm{Float64}(coeff,idxmap[var_idx])
    end
end

function _set_sum_of_objectives!(dest::MOI.ModelLike,srcs::Vector,idxmaps::Vector{MOIU.IndexMap})
    dest_obj = MOI.ScalarAffineFunction{Float64}(MOI.ScalarAffineTerm{Float64}[], 0.0)
    MOI.set(dest,MOI.ObjectiveSense(),MOI.MIN_SENSE)
    for (i,src) in enumerate(srcs)
        T = MOI.get(src,MOI.ObjectiveFunctionType())
        src_obj_to_add = copy(MOI.get(src,MOI.ObjectiveFunction{T}()))

        idxmap = idxmaps[i]

        #swap out variable indices for destination model
        _swap_indices!(src_obj_to_add,idxmap)

        #Fix objective sense
        if MOI.get(src,MOI.ObjectiveSense()) == MOI.MAX_SENSE
            src_obj_to_add = -1*src_obj_to_add
        end
        dest_obj += src_obj_to_add
    end
    MOI.set(dest,MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(),dest_obj)
    return dest_obj
end
##########################################################


# moi_mode(optimizer::AbstractNodeOptimizer) =
# moi_bridge_constraints(optimizer::AbstractNodeOptimizer) =

#Specialized methods
# function MOI.get(node_optimizer::NodeOptimizer, attr::Union{MOI.AbstractConstraintAttribute, MOI.AbstractModelAttribute, MOI.AbstractOptimizerAttribute, MOI.AbstractVariableAttribute})
#     return MOI.get(node_optimizer.optimizer,attr)
# end

#MOI.get(optimizer::AbstractNodeOptimizer,attr::MOI.AnyAttribute,args...) = MOI.get(optimizer.optimizer,attr,args...)
#This is ambiguous with: get(model::MathOptInterface.ModelLike, attr::MOI.AnyAttribute, idxs::Array{T,1} where T)


# function NodeOptimizer()
#     caching_mode = MOIU.AUTOMATIC
#     universal_fallback = MOIU.UniversalFallback(MOIU.Model{Float64}())
#     caching_opt = MOIU.CachingOptimizer(universal_fallback,caching_mode)
#     return NodeOptimizer(caching_opt)
# end

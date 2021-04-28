abstract type AbstractNodeBackend <: MOI.AbstractOptimizer end

"""
    Wrapper for a MOI.ModelLike Backend.  The `NodeBackend` makes it possible to use JuMP functions like `value` and `dual` on optinode variables without defining new variable and constraint types.  This is done by
    swapping out the `Model` backend with `NodeBackend`.  The idea is that Plasmo can just use native JuMP variable and constraint types.  A `NodeBackend` also supports multiple solutions per node.  This
    is helpful when the same node is part of multiple `OptiGraph` objects.
"""
mutable struct NodeBackend <: AbstractNodeBackend
    optimizer::MOI.ModelLike # optimizer::MOIU.CachingOptimizer
    id::Symbol
    primals::DefaultDict{Symbol,OrderedDict{MOI.VariableIndex,Float64}}
    duals::DefaultDict{Symbol,OrderedDict{MOI.ConstraintIndex,Float64}}
    nl_duals::DefaultDict{Symbol,OrderedDict{MOI.ConstraintIndex,Float64}}

    status::MOI.TerminationStatusCode

    idx_maps::DefaultDict{Symbol,MOIU.IndexMap}     #{node attributes => aggregate graph attributes}
    nl_idx_maps::DefaultDict{Symbol,OrderedDict}    #{node nl attributes => aggregate graph nl attributes}
    last_solution_id::Symbol                        #the last solution for this node backend
end

function NodeBackend(caching_opt::MOIU.CachingOptimizer,id::Symbol)
    return NodeBackend(
    caching_opt,
    id,
    DefaultDict{Symbol,OrderedDict{MOI.VariableIndex,Float64}}(OrderedDict{MOI.VariableIndex,Float64}()),
    DefaultDict{Symbol,OrderedDict{MOI.ConstraintIndex,Float64}}(OrderedDict{MOI.ConstraintIndex,Float64}()),
    DefaultDict{Symbol,OrderedDict{MOI.ConstraintIndex,Float64}}(OrderedDict{MOI.ConstraintIndex,Float64}()),
    MOI.OPTIMIZE_NOT_CALLED,
    DefaultDict{Symbol,MOIU.IndexMap}(MOIU.IndexMap()),
    DefaultDict{Symbol,OrderedDict}(OrderedDict()),
    id)
end

#Forward methods
MOI.add_variable(node_optimizer::NodeBackend) = MOI.add_variable(node_optimizer.optimizer)
MOI.add_constraint(node_optimizer::NodeBackend,func::MOI.AbstractFunction,set::MOI.AbstractSet) = MOI.add_constraint(node_optimizer.optimizer,func,set)
MOI.get(optimizer::NodeBackend,attr::MOI.AnyAttribute) = MOI.get(optimizer.optimizer,attr)
MOI.get(optimizer::NodeBackend,attr::MOI.AnyAttribute,idx) = MOI.get(optimizer.optimizer,attr,idx)
MOI.get(optimizer::NodeBackend,attr::MOI.AnyAttribute,idxs::Array{T,1} where T) = MOI.get(optimizer.optimizer,attr,idxs)
#NOTE: MOI.AnyAttribute = Union{MOI.AbstractConstraintAttribute, MOI.AbstractModelAttribute, MOI.AbstractOptimizerAttribute, MOI.AbstractVariableAttribute}
MOI.set(optimizer::NodeBackend,attr::MOI.AnyAttribute,args...) = MOI.set(optimizer.optimizer,attr,args...)
MOI.is_valid(optimizer::NodeBackend,idx::MOI.Index) = MOI.is_valid(optimizer.optimizer,idx)
MOI.delete(optimizer::NodeBackend, idx::MOI.Index) = MOI.delete(optimizer.optimizer,idx)
MOI.supports_constraint(optimizer::NodeBackend,func::Type{T}
    where T<:MathOptInterface.AbstractFunction, set::Type{S}
    where S <: MathOptInterface.AbstractSet) = MOI.supports_constraint(optimizer.optimizer,func,set)
MOI.supports(optimizer::NodeBackend, attr::Union{MOI.AbstractModelAttribute, MOI.AbstractOptimizerAttribute}) = MOI.supports(optimizer.optimizer,attr)
MOIU.attach_optimizer(optimizer::NodeBackend) = MOIU.attach_optimizer(optimizer.optimizer)
MOIU.drop_optimizer(optimizer::NodeBackend) = MOIU.drop_optimizer(optimizer.optimizer)
MOIU.reset_optimizer(optimizer::NodeBackend,args...) = MOIU.reset_optimizer(optimizer.optimizer,args...)
MOIU.state(optimizer::NodeBackend) = MOIU.state(optimizer.optimizer)

function set_node_primals!(backend::NodeBackend,vars::Vector{MOI.VariableIndex},values::Vector{Float64},id::Symbol)
    if length(vars) > 0
        primals = OrderedDict(zip(vars,values))
        backend.primals[id] = primals
    end
    return nothing
end

function set_node_duals!(backend::NodeBackend,cons::Vector,values::Vector{Float64},id::Symbol)
    if length(cons) > 0
        duals = OrderedDict(zip(cons,values))
        backend.duals[id] = duals
    end
    return nothing
end

"""
    Optimize the underlying optimizer and store the result in the node optimizer
"""
function MOI.optimize!(backend::NodeBackend)
    MOI.optimize!(backend.optimizer)

    #variable primals
    vars = MOI.get(backend.optimizer,MOI.ListOfVariableIndices())
    primals = MOI.get(backend.optimizer,MOI.VariablePrimal(),vars)

    #constraint duals
    cons = MOI.ConstraintIndex[]
    con_list = MOI.get(backend.optimizer,MOI.ListOfConstraints())
    cons = vcat([MOI.get(backend.optimizer,MOI.ListOfConstraintIndices{FS[1],FS[2]}()) for FS in con_list]...)
    duals = MOI.get(backend.optimizer,MOI.ConstraintDual(),cons)

    #Set node solution data for node id
    set_node_primals!(backend,vars,primals,backend.id)
    set_node_duals!(backend,cons,duals,backend.id)
    backend.status = MOI.get(backend.optimizer,MOI.TerminationStatus())

    #NOTE: Nonlinear duals should be in node.nlp_data.  TODO Copy them to backend.nl_duals[id]
    return nothing
end

#Get single variable index
function MOI.get(optimizer::NodeBackend, attr::MOI.VariablePrimal, idx::MOI.VariableIndex)
    return optimizer.primals[optimizer.last_solution_id][idx]
end

function MOI.get(optimizer::NodeBackend, attr::MOI.ConstraintDual, idx::MOI.ConstraintIndex)
    return optimizer.duals[optimizer.last_solution_id][idx]
end

#Get vector of primal values
function MOI.get(optimizer::NodeBackend, attr::MOI.VariablePrimal, idx::Vector{MOI.VariableIndex})
    return getindex.(Ref(optimizer.primals[optimizer.last_solution_id]),idx)
end

function MOI.get(backend::NodeBackend, attr::MOI.TerminationStatus)
    return backend.status
end

#AGGREGATE BACKENDS
#IDEA: Copy multiple moi backends without emptying the destination model.
function append_to_backend!(dest::MOI.ModelLike, src::MOI.ModelLike, copy_names::Bool;filter_constraints::Union{Nothing, Function}=nothing)

    vis_src = MOI.get(src, MOI.ListOfVariableIndices())   #returns vector of MOI.VariableIndex
    idxmap = MOI.Utilities.index_map_for_variable_indices(vis_src)

    constraint_types = MOI.get(src, MOI.ListOfConstraints())
    single_variable_types = [S for (F, S) in constraint_types if F == MOI.SingleVariable]
    vector_of_variables_types = [S for (F, S) in constraint_types if F == MOI.VectorOfVariables]
    vector_of_variables_not_added = [MOI.get(src, MOI.ListOfConstraintIndices{MOI.VectorOfVariables, S}()) for S in vector_of_variables_types]
    single_variable_not_added = [MOI.get(src, MOI.ListOfConstraintIndices{MOI.SingleVariable, S}()) for S in single_variable_types]

    #Copy free variables into graph optimizer
    MOI.Utilities.copy_free_variables(dest, idxmap, vis_src, MOI.add_variables)

    #Copy variable attributes (e.g. name, and VariablePrimalStart())
    MOI.Utilities.pass_attributes(dest, src, copy_names, idxmap, vis_src)

    # Normally, this copies ObjectiveSense and ObjectiveFunction, but we don't want to do that here
    #MOI.Utilities.pass_attributes(dest, src, copy_names, idxmap)

    #Copy constraints into graph optimizer
    MOI.Utilities.pass_constraints(dest, src, copy_names, idxmap,
                     single_variable_types, single_variable_not_added,
                     vector_of_variables_types, vector_of_variables_not_added,
                     filter_constraints=filter_constraints)

    return idxmap    #return an idxmap for each source model
end

#TODO: just set objective function from optigraph
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

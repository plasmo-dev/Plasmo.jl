abstract type AbstractNodeOptimizer <: MOI.AbstractOptimizer end

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
MOI.is_valid(optimizer::AbstractNodeOptimizer,idx::MOI.Index) = MOI.is_valid(optimizer.optimizer,idx)
MOI.delete(optimizer::NodeOptimizer, idx::MOI.Index) = MOI.delete(optimizer.optimizer,idx)
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

#IDEA: Update an existing graph optimizer (backend) with src model changes
function _update_backend_with_src!(id::Symbol,dest::MOI.ModelLike,src::MOI.ModelLike)
    vis_src = MOI.get(src,MOI.ListOfVariableIndices())
    src_idx_map = src.idx_maps[id]
    src_var_map = src_idx_map.varmap
    src_con_vamp = src_idx_map.conmap

    #COPY NEW VARIABLES TO GRAPH
    filter_to_add = filter((var) -> !(var in keys(src_var_map)), vis_src)
    update_idxmap = MOI.Utilities.index_map_for_variable_indices(filter_to_add)
    MOI.Utilities.copy_free_variables(dest, update_idxmap, filter_to_add, MOI.add_variables)
    merge!(src_idx_map,update_idxmap)

    #SET VARIABLE ATTRIBUTES TO CATCH VARIABLE UPDATES (e.g. primal starts)
    MOI.Utilities.pass_attributes(dest, src, false, src_idx_map, vis_src)

    #MODIFY CONSTRAINTS
    src_con_map = src_idx_map.conmap
    constraint_types = MOI.get(src,MOI.ListOfConstraints())
    cis_src = [MOI.get(src,MOI.ListOfConstraintIndices{F,S}()) for (F,S) in constraint_types]

    #DELETE CONSTRAINTS
    cis_src_vcat = vcat(cis_src...)
    cis_remove_from_idx_map = setdiff(keys(src_idx_map.conmap),cis_src_vcat)
    for cidx in cis_remove_from_idx_map
        MOI.delete(dest,src_idx_map.conmap[cidx])
        Base.delete!(src_idx_map,cidx)
    end

    #GET FILTER FOR NEWLY ADDED CONSTRAINTS
    filter_constraints = (cidx) -> !(cidx in keys(src_con_map))

    #GET SINGLE VARIABLE CONSTRAINTS
    single_variable_types = [S for (F, S) in constraint_types if F == MOI.SingleVariable]
    vector_of_variables_types = [S for (F, S) in constraint_types if F == MOI.VectorOfVariables]
    vector_of_variables_not_added = [MOI.get(src, MOI.ListOfConstraintIndices{MOI.VectorOfVariables, S}()) for S in vector_of_variables_types]
    single_variable_not_added = [MOI.get(src, MOI.ListOfConstraintIndices{MOI.SingleVariable, S}()) for S in single_variable_types]


    #PASS NEW CONSTRAINTS INTO GRAPH BACKEND
    dest_constraint_types = MOI.get(dest,MOI.ListOfConstraints())
    cis_dest = vcat([MOI.get(dest,MOI.ListOfConstraintIndices{F,S}()) for (F,S) in dest_constraint_types]...)
    MOI.Utilities.pass_constraints(dest, src, false, src_idx_map,
                     single_variable_types, single_variable_not_added,
                     vector_of_variables_types, vector_of_variables_not_added,
                     filter_constraints=filter_constraints)

    #This would update constraint attributes, such as names and possibly dual start
    for i = 1:length(cis_src)
        MOI.Utilities.pass_attributes(dest, src, false, src_idx_map,cis_src[i], MOI.set)
    end

    #TODO DELETE VARIABLES


    #UPDATE CONSTRAINT SETS
    for i = 1:length(cis_src)
        cis_src_to_check = cis_src[i]
        cis_dest_to_check = getindex.(Ref(src_idx_map),cis_src_to_check)

        src_con_set = MOI.get(src,MOI.ConstraintSet(),cis_src_to_check)
        dest_con_set = MOI.get(dest,MOI.ConstraintSet(),cis_dest_to_check)

        idx_to_set = findall(src_con_set .!= dest_con_set)
        for idx in idx_to_set
            MOI.set(dest,MOI.ConstraintSet(),cis_dest_to_check[idx],src_con_set[idx])
        end
    end

    #TODO: UPDATE CONSTRAINT FUNCS

    return src_idx_map
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


# NOTE: JuMP checks for NLPBlock and tries to constrain variables on creation otherwise
# The `NLPBlock` assumes that the order of variables does not change (#849)
# if MOI.NLPBlock() in MOI.get(src, MOI.ListOfModelAttributesSet())
#     constraint_types = MOI.get(src, MOI.ListOfConstraints())
#
#     single_variable_types = [S for (F, S) in constraint_types if F == MOI.SingleVariable]
#     vector_of_variables_types = [S for (F, S) in constraint_types if F == MOI.VectorOfVariables]
#
#     vector_of_variables_not_added = [MOI.get(src, MOI.ListOfConstraintIndices{MOI.VectorOfVariables, S}()) for S in vector_of_variables_types]
#     single_variable_not_added = [MOI.get(src, MOI.ListOfConstraintIndices{MOI.SingleVariable, S}()) for S in single_variable_types]
# else
#     #this collects the variable set types that the destination model supports
#     vector_of_variables_types, _, vector_of_variables_not_added,
#     single_variable_types, _, single_variable_not_added =
#     MOI.Utilities.try_constrain_variables_on_creation(dest, src, idxmap, MOI.add_constrained_variables, MOI.add_constrained_variable)
# end

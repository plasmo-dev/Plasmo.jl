#3 Cases
#1.) point to graph backend (other optimizer) to look up solution
#2.) Set the solution in a NodeSolution and point to that
#3.) Just use the node optimizer backend

abstract type AbstractNodeBackend <: MOI.AbstractOptimizer end
"""
    NodeSolution

        A struct holding primal values, dual values, and termination status values.  Used for setting custom solutions on optinodes without requiring an optimizer backend.
        For example, the `NodeSolution` backend supports MOI.get(backend::NodeSolution,MOI.VariablePrimal()) and MOI.set(backend::NodeSolution,MOI.VariablePrimal())
"""
mutable struct NodeSolution <: MOI.ModelLike
    primals::OrderedDict{MOI.VariableIndex,Float64}
    duals::OrderedDict{MOI.ConstraintIndex,Float64}
    status::MOI.TerminationStatusCode
end

NodeSolution(primals::OrderedDict{MOI.VariableIndex,Float64}) = NodeSolution(
primals,
OrderedDict{MOI.ConstraintIndex,Float64}(),
MOI.OPTIMIZE_NOT_CALLED)

NodeSolution(duals::OrderedDict{MOI.ConstraintIndex,Float64}) = NodeSolution(
OrderedDict{MOI.VariableIndex,Float64}(),
duals,
MOI.OPTIMIZE_NOT_CALLED)

NodeSolution(status::MOI.TerminationStatusCode) = NodeSolution(
OrderedDict{MOI.VariableIndex,Float64}(),
OrderedDict{MOI.ConstraintIndex,Float64}(),
status)

"""
    NodePointer

        A struct containing a reference to an MOI optimizer object.  The `NodePointer` "points" from local optinode variables and constraints to their location within an optimizer.
"""
mutable struct NodePointer <: MOI.ModelLike
    optimizer::MOI.ModelLike
    node_to_optimizer_map::MOIU.IndexMap
    nl_node_to_optimizer_map::OrderedDict
end
NodePointer(optimizer::MOI.ModelLike,idx_map::MOIU.IndexMap) = NodePointer(optimizer,idx_map,OrderedDict())


"""
    Wrapper for a MOI.ModelLike Backend.  The `NodeBackend` makes it possible to use JuMP functions like `value` and `dual` on optinode variables without defining new variable and constraint types.  This is done by
    swapping out the `Model` backend with `NodeBackend`.  The idea is that Plasmo can just use native JuMP variable and constraint types.  A `NodeBackend` also supports multiple solutions per node.  This
    is helpful when the same node is part of multiple `OptiGraph` objects.
"""
mutable struct NodeBackend <: AbstractNodeBackend
    optimizer::MOI.ModelLike                        #the base MOI model (e.g. a MOIU.CachingOptimizer)
    node_id::Symbol                                 #unique node id
    graph_ids::Vector{Symbol}                       #optigraph ids this node is a part of
    last_solution_id::Symbol                        #the last solution for this node
    optimizers::Dict{Symbol,MOI.ModelLike}          #All of the "optimizers" this node points to. can be the node itself, a custom NodeSolution, or a pointer to an optigraph optimizer
    result_location::Dict{Symbol,MOI.ModelLike}     #location to look up results (e.g. MOI.VariablePrimal())
    model_cache::Union{Nothing,MOI.ModelLike}
end

struct NodeCache <: MOI.ModelLike
    nb::NodeBackend
end

function NodeBackend(model::MOIU.CachingOptimizer,id::Symbol)
    node_backend = NodeBackend(
    model,
    id,
    Vector{Symbol}(),
    id,
    Dict{Symbol,MOI.ModelLike}(),
    Dict{Symbol,MOI.ModelLike}(),
    nothing)
    node_backend.model_cache = NodeCache(node_backend) #circular reference
    node_backend.optimizers[node_backend.node_id] = node_backend.optimizer #TODO: decide whether this is necessary
    # node_backend.model_cache = model.model_cache
    return node_backend
end

# model.moi_backend = MOI.Utilities.CachingOptimizer(backend(model).model_cache, optimizer)
function MOIU.CachingOptimizer(nodecache::NodeCache,optimizer::MOI.AbstractOptimizer)
    nb = nodecache.nb
    caching_optimizer = MOIU.CachingOptimizer(nb.optimizer.model_cache,optimizer)
    nb.optimizer = caching_optimizer
    return nb
end

#Custom MOI methods for optinodes
function MOI.add_variable(node_backend::NodeBackend)
    node_index = MOI.add_variable(node_backend.optimizer)
    for id in node_backend.graph_ids
        node_pointer = node_backend.optimizers[id]
        graph_index = MOI.add_variable(node_pointer.optimizer)
        node_pointer.node_to_optimizer_map[node_index] = graph_index
    end
    return node_index
end

#Add constraint to node MOI model and each graph optimizer it points to
function MOI.add_constraint(node_backend::NodeBackend,func::MOI.AbstractFunction,set::MOI.AbstractSet)
    node_index = MOI.add_constraint(node_backend.optimizer,func,set)
    for id in node_backend.graph_ids
        node_pointer = node_backend.optimizers[id]
        graph_func = _swap_indices(func,node_pointer.node_to_optimizer_map)
        graph_index = MOI.add_constraint(node_pointer.optimizer,graph_func,set)
        node_pointer.node_to_optimizer_map[node_index] = graph_index
    end
    return node_index
end

function MOI.delete(node_backend::NodeBackend, node_index::MOI.Index)
    MOI.delete(node_backend.optimizer,node_index)
    for id in node_backend.graph_ids
        node_pointer = node_backend.optimizers[id]
        graph_index = node_pointer.node_to_optimizer_map[node_index]
        MOI.delete(node_pointer.optimizer,graph_index)
        delete!(node_pointer.node_to_optimizer_map,node_index)
    end
end

#NOTE: MOI.AnyAttribute = Union{MOI.AbstractConstraintAttribute, MOI.AbstractModelAttribute, MOI.AbstractOptimizerAttribute, MOI.AbstractVariableAttribute}
function MOI.set(node_backend::Plasmo.NodeBackend,attr::MOI.AnyAttribute,args...)
    MOI.set(node_backend.optimizer,attr,args...)
    index_args = [arg for arg in args if isa(arg,MOI.Index)]
    other_args = [arg for arg in args if !isa(arg,MOI.Index)]
    for id in node_backend.graph_ids
        node_pointer = node_backend.optimizers[id]
        graph_indices = getindex.(Ref(node_pointer.node_to_optimizer_map),index_args)
        MOI.set(node_pointer.optimizer,attr,graph_indices...,other_args...)
    end
end

MOI.get(node_backend::NodeBackend,attr::MOI.AnyAttribute) = MOI.get(node_backend.optimizer,attr)
MOI.get(node_backend::NodeBackend,attr::MOI.AnyAttribute,idx) = MOI.get(node_backend.optimizer,attr,idx)
MOI.get(node_backend::NodeBackend,attr::MOI.AnyAttribute,idxs::Array{T,1} where T) = MOI.get(node_backend.optimizer,attr,idxs)
MOI.is_valid(node_backend::NodeBackend,idx::MOI.Index) = MOI.is_valid(node_backend.optimizer,idx)

MOI.supports_constraint(node_backend::NodeBackend,func::Type{T}
    where T<:MathOptInterface.AbstractFunction, set::Type{S}
    where S <: MathOptInterface.AbstractSet) = MOI.supports_constraint(node_backend.optimizer,func,set)
MOI.supports(node_backend::NodeBackend,
            attr::Union{MOI.AbstractModelAttribute,
            MOI.AbstractOptimizerAttribute}) =
            MOI.supports(node_backend.optimizer,attr)
MOI.supports(node_backend::NodeBackend,
            attr::MOI.AbstractVariableAttribute,
            idx = MOI.VariableIndex) =
            MOI.supports(node_backend.optimizer,attr,idx)

MOIU.attach_optimizer(node_backend::NodeBackend) = MOIU.attach_optimizer(node_backend.optimizer)
MOIU.drop_optimizer(node_backend::NodeBackend) = MOIU.drop_optimizer(node_backend.optimizer)
MOIU.reset_optimizer(node_backend::NodeBackend,args...) = MOIU.reset_optimizer(node_backend.optimizer,args...)
MOIU.state(node_backend::NodeBackend) = MOIU.state(node_backend.optimizer)

function has_node_solution(backend::NodeBackend,id::Symbol)
    if haskey(backend.result_location,id)
        return isa(backend.result_location[id],NodeSolution)
    else
        return false
    end
end

#These functions can be used to set custom solutions on a node.  Useful for meta-algorithms
function set_backend_primals!(backend::NodeBackend,vars::Vector{MOI.VariableIndex},values::Vector{Float64},id::Symbol)
    if length(vars) > 0
        #create node solution if necessary
        primals = OrderedDict(zip(vars,values))
        if !has_node_solution(backend,id)
            node_solution = NodeSolution(primals)
        else
            node_solution = backend.result_location[id]
            node_solution.primals = primals
        end
        backend.result_location[id] = node_solution
        backend.last_solution_id = id
    end
    return nothing
end

function set_backend_duals!(backend::NodeBackend,cons::Vector{MOI.ConstraintIndex},values::Vector{Float64},id::Symbol)
    if length(cons) > 0
        #create node solution if necessary
        duals = OrderedDict(zip(cons,values))
        if !has_node_solution(backend,id)
            node_solution = NodeSolution(duals)
        else
            node_solution = backend.result_location[id]
            node_solution.duals = duals
        end
        backend.last_solution_id = id
    end
    return nothing
end

function set_backend_status!(backend::NodeBackend,status::MOI.TerminationStatusCode,id::Symbol)
    if !has_node_solution(backend,id)
        node_solution = NodeSolution(status)
    else
        node_solution = backend.result_location[id]
        node_solution.status = status
    end
    backend.result_location[id] = node_solution
    backend.last_solution_id = id
    return nothing
end

"""
    Optimize the underlying optimizer and store the result in the node optimizer
"""
function MOI.optimize!(backend::NodeBackend)
    MOI.optimize!(backend.optimizer)
    backend.last_solution_id = backend.node_id
    return nothing
end

#Get node solution
MOI.get(node_solution::NodeSolution, attr::MOI.VariablePrimal, idx::MOI.VariableIndex) = node_solution.primals[idx]
MOI.get(node_solution::NodeSolution, attr::MOI.ConstraintDual, idx::MOI.ConstraintIndex) = node_solution.duals[idx]
MOI.get(node_solution::NodeSolution, attr::MOI.TerminationStatus) = node_solution.status
MOI.get(node_solution::NodeSolution, attr::MOI.VariablePrimal, idx::Vector{MOI.VariableIndex}) = getindex.(Ref(node_solution.primals),idx)

#Get node pointer solution
function MOI.get(node_pointer::NodePointer, attr::MOI.VariablePrimal, idx::MOI.VariableIndex)
    optimizer = node_pointer.optimizer
    other_index = node_pointer.node_to_optimizer_map[idx]
    value_other = MOI.get(optimizer,attr,other_index)
    return value_other
end

function MOI.get(node_pointer::NodePointer,attr::MOI.ConstraintDual, idx::MOI.ConstraintIndex)
    optimizer = node_pointer.optimizer
    other_index = node_pointer.node_to_optimizer_map[idx]
    value_other = MOI.get(optimizer,attr,other_index)
    return value_other
end
MOI.get(node_pointer::NodePointer, attr::MOI.TerminationStatus) = MOI.get(node_pointer.optimizer,attr)
MOI.set(node_pointer::NodePointer,attr::MOI.AnyAttribute,args...) = MOI.set(node_pointer.optimizer,attr,args...)

#Grab results from the underlying "optimizer"
function MOI.get(node_backend::NodeBackend, attr::MOI.VariablePrimal, idx::MOI.VariableIndex)
    return MOI.get(node_backend.result_location[node_backend.last_solution_id],attr,idx)
end

function MOI.get(node_backend::NodeBackend, attr::MOI.ConstraintDual, idx::MOI.ConstraintIndex)
    return MOI.get(node_backend.result_location[node_backend.last_solution_id],attr,idx)
end

#Get vector of variables
function MOI.get(node_backend::NodeBackend, attr::MOI.VariablePrimal, idx::Vector{MOI.VariableIndex})
    return MOI.get(node_backend.result_location[node_backend.last_solution_id],attr,idx)
end

function MOI.get(node_backend::NodeBackend, attr::MOI.ConstraintDual, idx::Vector{MOI.ConstraintIndex})
    return MOI.get(node_backend.result_location[node_backend.last_solution_id],attr,idx)
end

function MOI.get(node_backend::NodeBackend, attr::MOI.TerminationStatus)
    return MOI.get(node_backend.result_location[node_backend.last_solution_id],attr)
end

#####################################################
#The edge backend
#####################################################
#A custom-set edge dual solution
mutable struct EdgeSolution <: MOI.ModelLike
    duals::OrderedDict{MOI.ConstraintIndex,Float64}
    status::MOI.TerminationStatusCode
end

#An EdgePointer 'points' to an optimizer
mutable struct EdgePointer <: MOI.ModelLike
    optimizer::MOI.ModelLike
    edge_to_optimizer_map::OrderedDict{AbstractLinkConstraintRef,MOI.ConstraintIndex}
end
EdgePointer(optimizer::MOI.ModelLike) = EdgePointer(optimizer,OrderedDict{AbstractLinkConstraintRef,MOI.ConstraintIndex}())

mutable struct EdgeBackend <: MOI.AbstractOptimizer
    optimizers::Dict{Symbol,MOI.ModelLike}
    last_solution_id::Union{Nothing,Symbol}                        #the last solution for this node backend
    result_location::Dict{Symbol,MOI.ModelLike}
end
EdgeBackend() = EdgeBackend(Dict{Symbol,MOI.ModelLike}(),nothing,Dict{Symbol,MOI.ModelLike}())

#get EdgeBackend
function MOI.get(edge_backend::EdgeBackend,  attr::MOI.ConstraintDual, ref::AbstractLinkConstraintRef)
    return MOI.get(edge_backend.result_location[edge_backend.last_solution_id],attr,ref)
end

#get EdgeSolution
MOI.get(edge_solution::EdgeSolution, attr::MOI.TerminationStatus) = edge_solution.status
MOI.get(edge_solution::EdgeSolution, attr::MOI.ConstraintDual, idx::MOI.ConstraintIndex) = edge_solution.duals[idx]

#get EdgePointer
function MOI.get(edge_pointer::EdgePointer,attr::MOI.ConstraintDual, ref::AbstractLinkConstraintRef)
    optimizer = edge_pointer.optimizer
    optimizer_index = edge_pointer.edge_to_optimizer_map[ref]
    optimizer_value = MOI.get(optimizer,attr,optimizer_index)
    return optimizer_value
end
MOI.get(edge_pointer::EdgePointer, attr::MOI.TerminationStatus) = MOI.get(edge_pointer.optimizer,attr)

#Helpful utilities
#SingleVariable is no longer a MOI type
# function _swap_indices(variable::MOI.SingleVariable,idxmap::MOIU.IndexMap)
#     return idxmap[variable.variable]
# end
function _swap_indices(variable::MOI.VariableIndex,idxmap::MOIU.IndexMap)
    return idxmap[variable]
end

function _swap_indices(func::MOI.ScalarAffineFunction,idxmap::MOIU.IndexMap)
    new_func = copy(func)
    terms = new_func.terms
    for i = 1:length(terms)
        coeff = terms[i].coefficient
        var_idx = terms[i].variable_index
        terms[i] = MOI.ScalarAffineTerm{Float64}(coeff,idxmap[var_idx])
    end
    return new_func
end

#TODO: Quadratic swap
# function _swap_indices(obj::MOI.ScalarQuadraticFunction,idxmap::MOIU.IndexMap)
#     quad_terms = obj.quadratic_terms
#     for i = 1:length(quad_terms)
#         coeff = quad_terms[i].coefficient
#         var_idx1 = quad_terms[i].variable_index_1
#         var_idx2 = quad_terms[i].variable_index_2
#         quad_terms[i] = MOI.ScalarQuadraticTerm{Float64}(coeff,idxmap[var_idx1],idxmap[var_idx2])
#     end
#     aff_terms = obj.affine_terms
#     for i = 1:length(aff_terms)
#         coeff = aff_terms[i].coefficient
#         var_idx = aff_terms[i].variable_index
#         terms[i] = MOI.ScalarAffineTerm{Float64}(coeff,idxmap[var_idx])
#     end
# end

"""
    Mapping of node variables and constraints to the optigraph backend.
"""
mutable struct NodeToGraphMap
    var_map::OrderedDict{NodeVariableRef,MOI.VariableIndex}
    con_map::OrderedDict{ConstraintRef,MOI.ConstraintIndex}
end
function NodeToGraphMap()
    return NodeToGraphMap(
        OrderedDict{NodeVariableRef,MOI.VariableIndex}(),
        OrderedDict{ConstraintRef,MOI.ConstraintIndex}(),
    )
end

function Base.setindex!(n2g_map::NodeToGraphMap, idx::MOI.VariableIndex, vref::NodeVariableRef)
    n2g_map.var_map[vref] = idx
    return
end

function Base.getindex(n2g_map::NodeToGraphMap, vref::NodeVariableRef)
    return n2g_map.var_map[vref]
end

function Base.setindex!(n2g_map::NodeToGraphMap, idx::MOI.ConstraintIndex, cref::ConstraintRef)
    n2g_map.con_map[cref] = idx
    return
end

function Base.getindex(n2g_map::NodeToGraphMap, cref::ConstraintRef)
    return n2g_map.con_map[cref]
end

"""
    Mapping of graph backend variable and constraint indices to 
    node variables and constraints.
"""
mutable struct GraphToNodeMap
    var_map::OrderedDict{MOI.VariableIndex,NodeVariableRef}
    con_map::OrderedDict{MOI.ConstraintIndex,ConstraintRef}
end
function GraphToNodeMap()
    return GraphToNodeMap(
        OrderedDict{MOI.VariableIndex,NodeVariableRef}(),
        OrderedDict{MOI.ConstraintIndex,ConstraintRef}(),
    )
end

function Base.setindex!(g2n_map::GraphToNodeMap,  vref::NodeVariableRef, idx::MOI.VariableIndex)
    g2n_map.var_map[idx] = vref
    return
end

function Base.getindex(g2n_map::GraphToNodeMap, idx::MOI.VariableIndex)
    return g2n_map.var_map[idx]
end

function Base.setindex!(g2n_map::GraphToNodeMap,  cref::ConstraintRef, idx::MOI.ConstraintIndex)
    g2n_map.con_map[idx] = cref
    return
end

function Base.getindex(g2n_map::GraphToNodeMap, idx::MOI.ConstraintIndex)
    return g2n_map.con_map[idx]
end

# acts as an intermediate optimizer, except it uses references to underlying nodes in the graph
# NOTE: OptiGraph does not support modes yet. Eventually we will support more than CachingOptimizer
# try to support Direct, Manual, and Automatic modes on an optigraph.
mutable struct GraphMOIBackend <: MOI.AbstractOptimizer
    optigraph::AbstractOptiGraph
    # TODO: legacy nlp model
    # nlp_model::MOI.Nonlinear.Model
    moi_backend::MOI.AbstractOptimizer
    node_to_graph_map::NodeToGraphMap
    graph_to_node_map::GraphToNodeMap
end

"""
    GraphMOIBackend()

Initialize an empty optigraph backend. Contains a model_cache that can be used to set
`MOI.AbstractModelAttribute`s and `MOI.AbstractOptimizerAttribute`s. By default we 
use a `CachingOptimizer` to store the underlying optimizer.
"""
function GraphMOIBackend(optigraph::AbstractOptiGraph)
    inner = MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}())
    cache = MOI.Utilities.CachingOptimizer(inner, MOI.Utilities.AUTOMATIC)
    return GraphMOIBackend(
        optigraph,
        cache,
        NodeToGraphMap(),
        GraphToNodeMap()
    )
end

# JuMP Extension

function JuMP.backend(gb::GraphMOIBackend)
    return gb.moi_backend
end

# MOI Extension

function MOI.get(gb::GraphMOIBackend, attr::MOI.AnyAttribute)
    return MOI.get(gb.moi_backend, attr)
end

function MOI.get(gb::GraphMOIBackend, attr::MOI.AnyAttribute, ref::ConstraintRef)
    graph_index = gb.node_to_graph_map[ref]
    return MOI.get(gb.moi_backend, attr, graph_index)
end

function MOI.get(gb::GraphMOIBackend, attr::MOI.AnyAttribute, ref::NodeVariableRef)
    graph_index = gb.node_to_graph_map[ref]
    return MOI.get(gb.moi_backend, attr, graph_index)
end

function MOI.set(graph_backend::GraphMOIBackend, attr::MOI.AnyAttribute, args...)
    MOI.set(graph_backend.moi_backend, attr, args...)
end

### Variables

function next_variable_index(node::OptiNode)
    return MOI.VariableIndex(num_variables(node) + 1)
end

function _moi_add_node_variable(
    node::OptiNode,
    v::JuMP.AbstractVariable
)
    # get node index and create variable reference
    variable_index = next_variable_index(node)
    vref = NodeVariableRef(node, variable_index)
    # add variable to all containing optigraphs
    for graph in containing_optigraphs(node)
        graph_var_index = _add_variable_to_backend(graph_backend(graph), vref)
         _moi_constrain_node_variable(
            graph_backend(graph),
            graph_var_index,
            v.info, 
            Float64
        )
    end
    return vref
end

function _add_variable_to_backend(
    graph_backend::GraphMOIBackend,
    vref::NodeVariableRef
)
    graph_var_index = MOI.add_variable(graph_backend.moi_backend)
    graph_backend.node_to_graph_map[vref] = graph_var_index
    graph_backend.graph_to_node_map[graph_var_index] = vref
    return graph_var_index
end

### Node Constraints

function next_constraint_index(
    node::OptiNode, 
    ::Type{F}, 
    ::Type{S}
)::MOI.ConstraintIndex{F,S} where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    index = num_constraints(node, F, S)
    return MOI.ConstraintIndex{F,S}(index + 1)
end

function _moi_add_node_constraint(
    node::OptiNode,
    con::JuMP.AbstractConstraint
)
    # get moi function and set
    jump_func = JuMP.jump_function(con)
    moi_func = JuMP.moi_function(con)
    moi_set = JuMP.moi_set(con)

    constraint_index = next_constraint_index(
        node, 
        typeof(moi_func), 
        typeof(moi_set)
    )::MOI.ConstraintIndex{typeof(moi_func),typeof(moi_set)}
    cref = ConstraintRef(node, constraint_index, JuMP.shape(con))

    for graph in containing_optigraphs(node)
        # TODO: i think we need to make copies here for moi_funcs
        # moi_func_graph = copy(moi_func)
        # update func variable indices
        _update_moi_func!(graph_backend(graph), moi_func, jump_func)

        # add to optinode backend
        _add_node_constraint_to_backend(graph_backend(graph), cref, moi_func, moi_set)
    end
    return cref
end

function _add_node_constraint_to_backend(
    graph_backend::GraphMOIBackend,
    cref::ConstraintRef,
    func::F,
    set::S
) where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    graph_con_index = MOI.add_constraint(graph_backend.moi_backend, func, set)
    graph_backend.node_to_graph_map[cref] = graph_con_index
    graph_backend.graph_to_node_map[graph_con_index] = cref
    return graph_con_index
end

### Edge Constraints

function next_constraint_index(
    edge::OptiEdge, 
    ::Type{F}, 
    ::Type{S}
)::MOI.ConstraintIndex{F,S} where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    index = num_constraints(edge, F, S)
    return MOI.ConstraintIndex{F,S}(index + 1)
end

### MOI Utilities

"""
    _update_moi_func!(
        backend::GraphMOIBackend,
        moi_func::MOI.ScalarAffineFunction,
        jump_func::JuMP.GenericAffExpr
    )

Update an MOI function with the actual variable indices from a backend graph.
"""
function _update_moi_func!(
    backend::GraphMOIBackend,
    moi_func::MOI.ScalarAffineFunction,
    jump_func::JuMP.GenericAffExpr
)
    for (i, term) in enumerate(JuMP.linear_terms(jump_func))
        coeff = term[1]
        var = term[2]
        backend_var_idx = backend.node_to_graph_map[var]
        moi_func.terms[i] = MOI.ScalarAffineTerm{Float64}(coeff, backend_var_idx)
    end
    return
end

function _update_moi_func!(
    backend::GraphMOIBackend,
    moi_func::MOI.ScalarQuadraticFunction,
    jump_func::JuMP.GenericQuadExpr
)
    #quadratic terms
    for (i, term) in enumerate(JuMP.quad_terms(jump_func))
        coeff = term[1]
        var1 = term[2]
        var2 = term[3]
        var_idx_1 = backend.node_to_graph_map[var1]
        var_idx_2 = backend.node_to_graph_map[var2]

        moi_func.quadratic_terms[i] = MOI.ScalarQuadraticTerm{Float64}(
            coeff, 
            var_idx_1, 
            var_idx_2
        )
    end

    # linear terms
    for (i, term) in enumerate(JuMP.linear_terms(jump_func))
        coeff = term[1]
        var = term[2]
        backend_var_idx = backend.node_to_graph_map[var]
        moi_func.affine_terms[i] = MOI.ScalarAffineTerm{Float64}(coeff, backend_var_idx)
    end
    return
end

function _update_moi_func!(
    backend::GraphMOIBackend,
    moi_func::MOI.ScalarNonlinearFunction,
    jump_func::JuMP.GenericNonlinearExpr
)
    for i = 1:length(jump_func.args)
        jump_arg = jump_func.args[i]
        moi_arg = moi_func.args[i]
        if typeof(jump_arg) == JuMP.GenericNonlinearExpr
            _update_moi_func!(backend, moi_arg, jump_arg)
        elseif typeof(jump_arg) == NodeVariableRef
            moi_func.args[i] = backend.node_to_graph_map[jump_arg]
        end
    end
    return
end

function _add_backend_variables(
    backend::GraphMOIBackend,
    jump_func::JuMP.GenericAffExpr
)
    vars = [term[2] for term in JuMP.linear_terms(jump_func)]
    vars_to_add = setdiff(vars, keys(backend.node_to_graph_map.var_map))
    for var in vars_to_add
        _add_variable_to_backend(backend, var)
    end
    return
end

function _add_backend_variables(
    backend::GraphMOIBackend,
    jump_func::JuMP.GenericQuadExpr
)
    vars_aff = [term[2] for term in JuMP.linear_terms(jump_func)]
    vars_quad = vcat([[term[2], term[3]] for term in JuMP.quad_terms(jump_func)]...)
    vars_unique = unique([vars_aff;vars_quad])
    vars_to_add = setdiff(vars_unique, keys(backend.node_to_graph_map.var_map))
    for var in vars_to_add
        _add_variable_to_backend(backend, var)
    end
    return
end

function _add_backend_variables(
    backend::GraphMOIBackend,
    jump_func::JuMP.GenericNonlinearExpr
)
    vars = NodeVariableRef[]
    for i = 1:length(jump_func.args)
        jump_arg = jump_func.args[i]
        if typeof(jump_arg) == JuMP.GenericNonlinearExpr
            _add_backend_variables(backend, jump_arg)
        elseif typeof(jump_arg) == NodeVariableRef
            push!(vars, jump_arg)
        end
    end

    vars_to_add = setdiff(vars, keys(backend.node_to_graph_map.var_map))
    for var in vars_to_add
        _add_variable_to_backend(backend, var)
    end
    return
end

function _moi_add_edge_constraint(
    edge::OptiEdge,
    con::JuMP.AbstractConstraint
)
    # get moi function and set
    jump_func = JuMP.jump_function(con)
    moi_func = JuMP.moi_function(con)
    moi_set = JuMP.moi_set(con)

    # create constraint index and reference
    constraint_index = next_constraint_index(
        edge, 
        typeof(moi_func), 
        typeof(moi_set)
    )::MOI.ConstraintIndex{typeof(moi_func),typeof(moi_set)}
    cref = ConstraintRef(edge, constraint_index, JuMP.shape(con))

    # update graph backends
    for graph in containing_optigraphs(edge)
        # add backend variables if linking across optigraphs
        _add_backend_variables(graph_backend(graph), jump_func)

        # update the moi function variable indices
        _update_moi_func!(graph_backend(graph), moi_func, jump_func)

        # add the constraint to the backend
        _add_edge_constraint_to_backend(graph_backend(graph), cref, moi_func, moi_set)
    end

    return cref
end

function _add_edge_constraint_to_backend(
    graph_backend::GraphMOIBackend,
    cref::ConstraintRef,
    func::F,
    set::S
) where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    graph_con_index = MOI.add_constraint(graph_backend.moi_backend, func, set)
    graph_backend.node_to_graph_map[cref] = graph_con_index
    graph_backend.graph_to_node_map[graph_con_index] = cref
    return graph_con_index
end

### Objective Function

function _moi_set_objective_function(
    graph::OptiGraph, 
    expr::JuMP.GenericAffExpr{C,NodeVariableRef}
) where C <: Real
    moi_func = JuMP.moi_function(expr)
    
    # add variables to backend if using subgraphs
    _add_backend_variables(graph_backend(graph), expr)

    # update the moi function variable indices
    _update_moi_func!(graph_backend(graph), moi_func, expr)

    MOI.set(
        graph_backend(graph),
        MOI.ObjectiveFunction{MOI.ScalarAffineFunction{C}}(),
        moi_func,
    )
    return
end

function _moi_set_objective_function(
    graph::OptiGraph, 
    expr::JuMP.GenericQuadExpr{C,NodeVariableRef}
) where C <: Real
    moi_func = JuMP.moi_function(expr)
    
    # add variables to backend if using subgraphs
    _add_backend_variables(graph_backend(graph), expr)

    # update the moi function variable indices
    _update_moi_func!(graph_backend(graph), moi_func, expr)

    MOI.set(
        graph_backend(graph),
        MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{C}}(),
        moi_func,
    )
    return
end

function _moi_set_objective_function(
    graph::OptiGraph, 
    expr::JuMP.GenericNonlinearExpr{NodeVariableRef}
)
    moi_func = JuMP.moi_function(expr)
    
    # add variables to backend if using subgraphs
    _add_backend_variables(graph_backend(graph), expr)

    # update the moi function variable indices
    _update_moi_func!(graph_backend(graph), moi_func, expr)

    MOI.set(
        graph_backend(graph),
        MOI.ObjectiveFunction{MOI.ScalarNonlinearFunction}(),
        moi_func,
    )
    return
end

function MOI.optimize!(graph_backend::GraphMOIBackend)
    MOI.optimize!(graph_backend.moi_backend)
    return nothing
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

#     # per the comment in MOI:
#     # "The `NLPBlock` assumes that the order of variables does not change (#849)
#     # Therefore, all VariableIndex and VectorOfVariable constraints are added
#     # seprately, and no variables constrained-on-creation are added.""
#     # Consequently, Plasmo avoids using the constrained-on-creation approach because
#     # of the way it constructs the NLPBlock for the optimizer.

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
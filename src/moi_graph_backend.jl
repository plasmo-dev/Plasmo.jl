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

# mutable struct NodeToGraphMap
#     var_map::OrderedDict{NodeVariableRef,MOI.VariableIndex}
#     con_map::OrderedDict{ConstraintRef,MOI.ConstraintIndex}
# end
# function NodeToGraphMap()
#     return NodeToGraphMap(
#         OrderedDict{NodeVariableRef,MOI.VariableIndex}(),
#         OrderedDict{ConstraintRef,MOI.ConstraintIndex}(),
#     )
# end


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
    # TODO (maybe): legacy nlp model
    # nlp_model::MOI.Nonlinear.Model
    moi_backend::MOI.AbstractOptimizer
    node_to_graph_map::NodeToGraphMap
    graph_to_node_map::GraphToNodeMap
    node_variables::OrderedDict{OptiNode,Vector{MOI.VariableIndex}}
    node_constraints::OrderedDict{OptiNode,Vector{MOI.ConstraintIndex}}
end

"""
    GraphMOIBackend()

Initialize an empty optigraph backend that uses MOI. 
By default we use a `CachingOptimizer` to store the underlying optimizer just like JuMP.
"""
function GraphMOIBackend(optigraph::AbstractOptiGraph)
    inner = MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}())
    cache = MOI.Utilities.CachingOptimizer(inner, MOI.Utilities.AUTOMATIC)
    return GraphMOIBackend(
        optigraph,
        cache,
        NodeToGraphMap(),
        GraphToNodeMap(),
        OrderedDict{OptiNode,Vector{MOI.VariableIndex}}(),
        OrderedDict{OptiNode,Vector{MOI.ConstraintIndex}}()
    )
end

function add_node(gb::GraphMOIBackend, node::OptiNode)
    gb.node_variables[node] = MOI.VariableIndex[]
    gb.node_constraints[node] = MOI.ConstraintIndex[]
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
        push!(graph_backend(graph).node_variables[node], graph_var_index)
        _moi_constrain_node_variable(
            graph_backend(graph),
            node,
            graph_var_index,
            v.info, 
            Float64
        )
    end
    return vref
end

function _moi_constrain_node_variable(
    gb::GraphMOIBackend,
    node::OptiNode,
    index,
    info,
    ::Type{T},
) where {T}
    #TODO: set local node constraint indices
    if info.has_lb
        # next_node_index = next_constraint_index(node, MOI.VariableIndex, MOI.GreaterThan{T})
        con = _moi_add_constraint(
            gb.moi_backend,
            index,
            MOI.GreaterThan{T}(info.lower_bound),
        )
        push!(gb.node_constraints[node], con)
        #push!(gb.node_constraints[node], next_node_index)
        # gb.node_to_graph_map.con_map[next_node_index] = con
        # gb.graph_to_node_map.con_map[con] = next_node_index
    end
    if info.has_ub
        con = _moi_add_constraint(
            gb.moi_backend,
            index,
            MOI.LessThan{T}(info.upper_bound),
        )
        push!(gb.node_constraints[node], con)
    end
    if info.has_fix
        con = _moi_add_constraint(
            gb.moi_backend,
            index,
            MOI.EqualTo{T}(info.fixed_value),
        )
        push!(gb.node_constraints[node], con)
    end
    if info.binary
        con = _moi_add_constraint(gb.moi_backend, index, MOI.ZeroOne())
        push!(gb.node_constraints[node], con)
    end
    if info.integer
        con = _moi_add_constraint(gb.moi_backend, index, MOI.Integer())
        push!(gb.node_constraints[node], con)
    end
    if info.has_start && info.start !== nothing
        MOI.set(
            gb.moi_backend,
            MOI.VariablePrimalStart(),
            index,
            convert(T, info.start),
        )
    end
end

function _add_variable_to_backend(
    graph_backend::GraphMOIBackend,
    vref::NodeVariableRef
)
    # return if variable already in backend
    vref in keys(graph_backend.node_to_graph_map.var_map) && return

    # add variable, track index
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
        moi_func_graph = deepcopy(moi_func)

        # update func variable indices
        _update_moi_func!(graph_backend(graph), moi_func_graph, jump_func)

        # add to optinode backend
        _add_node_constraint_to_backend(graph_backend(graph), cref, moi_func_graph, moi_set)
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

#TODO: use copies for updating
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
        if jump_arg isa JuMP.GenericNonlinearExpr
            _update_moi_func!(backend, moi_arg, jump_arg)
        elseif typeof(jump_arg) == NodeVariableRef
            moi_func.args[i] = backend.node_to_graph_map[jump_arg]
        end
    end
    return
end

### add variables to a backend for purpose of creating linking constraints or objectives 
# across subgraphs

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

        moi_func_graph = deepcopy(moi_func)

        # update the moi function variable indices
        _update_moi_func!(graph_backend(graph), moi_func_graph, jump_func)

        # add the constraint to the backend
        _add_edge_constraint_to_backend(graph_backend(graph), cref, moi_func_graph, moi_set)
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
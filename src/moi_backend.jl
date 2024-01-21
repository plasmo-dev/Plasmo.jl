"""
    Mapping of node variables and constraints to the optigraph backend.
"""
mutable struct ElementToGraphMap
    var_map::OrderedDict{NodeVariableRef,MOI.VariableIndex}
    con_map::OrderedDict{ConstraintRef,MOI.ConstraintIndex}
end
function ElementToGraphMap()
    return ElementToGraphMap(
        OrderedDict{NodeVariableRef,MOI.VariableIndex}(),
        OrderedDict{ConstraintRef,MOI.ConstraintIndex}(),
    )
end

function Base.setindex!(n2g_map::ElementToGraphMap, idx::MOI.VariableIndex, vref::NodeVariableRef)
    n2g_map.var_map[vref] = idx
    return
end

function Base.getindex(n2g_map::ElementToGraphMap, vref::NodeVariableRef)
    return n2g_map.var_map[vref]
end

function Base.setindex!(n2g_map::ElementToGraphMap, idx::MOI.ConstraintIndex, cref::ConstraintRef)
    n2g_map.con_map[cref] = idx
    return
end

function Base.getindex(n2g_map::ElementToGraphMap, cref::ConstraintRef)
    return n2g_map.con_map[cref]
end

"""
    Mapping of graph backend variable and constraint indices to 
    node variables and constraints.
"""
mutable struct GraphToElementMap
    var_map::OrderedDict{MOI.VariableIndex,NodeVariableRef}
    con_map::OrderedDict{MOI.ConstraintIndex,ConstraintRef}
end
function GraphToElementMap()
    return GraphToElementMap(
        OrderedDict{MOI.VariableIndex,NodeVariableRef}(),
        OrderedDict{MOI.ConstraintIndex,ConstraintRef}(),
    )
end

function Base.setindex!(g2element_map::GraphToElementMap,  vref::NodeVariableRef, idx::MOI.VariableIndex)
    g2element_map.var_map[idx] = vref
    return
end

function Base.getindex(g2element_map::GraphToElementMap, idx::MOI.VariableIndex)
    return g2element_map.var_map[idx]
end

function Base.setindex!(g2element_map::GraphToElementMap,  cref::ConstraintRef, idx::MOI.ConstraintIndex)
    g2element_map.con_map[idx] = cref
    return
end

function Base.getindex(g2element_map::GraphToElementMap, idx::MOI.ConstraintIndex)
    return g2element_map.con_map[idx]
end

# acts as an intermediate optimizer, except it uses references to underlying nodes in the graph
# NOTE: OptiGraph does not support modes yet. Eventually we will support more than CachingOptimizer
# try to support Direct, Manual, and Automatic modes on an optigraph.
mutable struct GraphMOIBackend <: MOI.AbstractOptimizer
    optigraph::AbstractOptiGraph
    moi_backend::MOI.AbstractOptimizer
    
    element_to_graph_map::ElementToGraphMap
    graph_to_element_map::GraphToElementMap

    # map of variables and constraints on nodes and edges to graph backend indices
    node_variables::OrderedDict{OptiNode,Vector{MOI.VariableIndex}}
    element_constraints::OrderedDict{OptiElement,Vector{MOI.ConstraintIndex}}

    # TODO (maybe): legacy JuMP nonlinear support
    # nlp_model::MOI.Nonlinear.Model
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
        ElementToGraphMap(),
        GraphToElementMap(),
        OrderedDict{OptiNode,Vector{MOI.VariableIndex}}(),
        OrderedDict{OptiElement,Vector{MOI.ConstraintIndex}}()
    )
end

function add_node(gb::GraphMOIBackend, node::OptiNode)
    gb.node_variables[node] = MOI.VariableIndex[]
    gb.element_constraints[node] = MOI.ConstraintIndex[]
end

function add_edge(gb::GraphMOIBackend, edge::OptiEdge)
    gb.element_constraints[edge] = MOI.ConstraintIndex[]
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
    graph_index = gb.element_to_graph_map[ref]
    return MOI.get(gb.moi_backend, attr, graph_index)
end

function MOI.get(gb::GraphMOIBackend, attr::MOI.AnyAttribute, ref::NodeVariableRef)
    graph_index = gb.element_to_graph_map[ref]
    return MOI.get(gb.moi_backend, attr, graph_index)
end

function MOI.set(gb::GraphMOIBackend, attr::MOI.AnyAttribute, args...)
    MOI.set(gb.moi_backend, attr, args...)
    return
end

function MOI.delete(gb::GraphMOIBackend, nvref::NodeVariableRef)
    MOI.delete(gb.moi_backend, gb.element_to_graph_map[nvref])
    delete!(gb.graph_to_element_map.var_map, gb.element_to_graph_map[nvref])
    delete!(gb.element_to_graph_map.var_map, nvref)
    return
end

function MOI.delete(gb::GraphMOIBackend, cref::ConstraintRef)
    MOI.delete(gb.moi_backend, gb.element_to_graph_map[cref])
    delete!(gb.graph_to_element_map.con_map, gb.element_to_graph_map[cref])
    delete!(gb.element_to_graph_map.con_map, cref)
    return
end

function MOI.is_valid(gb::GraphMOIBackend, vi::MOI.VariableIndex)
    return MOI.is_valid(gb.moi_backend, vi)
end

function MOI.is_valid(gb::GraphMOIBackend, ci::MOI.ConstraintIndex)
    return MOI.is_valid(gb.moi_backend, ci)
end

### Variables

function next_variable_index(node::OptiNode)
    return MOI.VariableIndex(JuMP.num_variables(node) + 1)
end

function graph_index(gb::GraphMOIBackend, nvref::NodeVariableRef)
    return gb.element_to_graph_map[nvref]
end

# add variable

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
            vref,
            v.info, 
            Float64
        )
    end
    return vref
end

function _moi_constrain_node_variable(
    gb::GraphMOIBackend,
    vref::NodeVariableRef,
    info,
    ::Type{T},
) where {T}
    graph_index = gb.element_to_graph_map[vref]
    if info.has_lb
        con = JuMP.ScalarConstraint(vref, MOI.GreaterThan{T}(info.lower_bound))
        _moi_add_node_constraint(vref.node, con)
    end
    if info.has_ub
        con = JuMP.ScalarConstraint(vref, MOI.LessThan{T}(info.upper_bound))
        _moi_add_node_constraint(vref.node, con)
    end
    if info.has_fix
        con = JuMP.ScalarConstraint(vref, MOI.EqualTo{T}(info.fixed_value))
        _moi_add_node_constraint(vref.node, con)
    end
    if info.binary
        con = JuMP.ScalarConstraint(vref, MOI.ZeroOne())
        _moi_add_node_constraint(vref.node, con)
    end
    if info.integer
        con = JuMP.ScalarConstraint(vref, MOI.Integer())
        _moi_add_node_constraint(vref.node, con)
    end
    if info.has_start && info.start !== nothing
        MOI.set(
            gb.moi_backend,
            MOI.VariablePrimalStart(),
            graph_index,
            convert(T, info.start),
        )
    end
end

function _add_variable_to_backend(
    graph_backend::GraphMOIBackend,
    vref::NodeVariableRef
)
    # return if variable already in backend
    vref in keys(graph_backend.element_to_graph_map.var_map) && return

    # add variable, track index
    graph_var_index = MOI.add_variable(graph_backend.moi_backend)
    graph_backend.element_to_graph_map[vref] = graph_var_index
    graph_backend.graph_to_element_map[graph_var_index] = vref

    # create key for node if necessary
    if !haskey(graph_backend.node_variables, vref.node)
        graph_backend.node_variables[vref.node] = MOI.VariableIndex[]
    end
    push!(graph_backend.node_variables[vref.node], graph_var_index)
    return graph_var_index
end

# fix/unfix variable

function _moi_fix_node_variable(
    nvref::NodeVariableRef,
    value::Number,
    force::Bool,
    ::Type{T}
) where {T}
    new_set = MOI.EqualTo(convert(T, value))
    if _moi_nv_is_fixed(nvref)
        cref = _nv_fix_ref(nvref)
        # updates each backend graph
        MOI.set(nvref.node, MOI.ConstraintSet(), cref, new_set)
    else  
        # add a new fixing constraint
        if _moi_nv_has_upper_bound(nvref) ||
           _moi_nv_has_lower_bound(nvref)
            if !force
                error(
                    "Unable to fix $(nvref) to $(value) because it has " *
                    "existing variable bounds. Consider calling " *
                    "`JuMP.fix(variable, value; force=true)` which will " *
                    "delete existing bounds before fixing the variable.",
                )
            end
            if _moi_nv_has_upper_bound(nvref)
                MOI.delete(nvref.node, _nv_upper_bound_ref(nvref))
            end
            if _moi_nv_has_lower_bound(nvref)
                MOI.delete(nvref.node, _nv_lower_bound_ref(nvref))
            end
        end
        con = JuMP.ScalarConstraint(nvref, MOI.EqualTo{T}(value))
        _moi_add_node_constraint(nvref.node, con)
    end
    return
end

function _moi_nv_is_fixed(nvref::NodeVariableRef)
    gb = graph_backend(nvref.node)
    ci = MOI.ConstraintIndex{MOI.VariableIndex,MOI.EqualTo{Float64}}(
        gb.element_to_graph_map[nvref].value
    )
    return MOI.is_valid(graph_backend(nvref.node), ci)
end

function _nv_fix_ref(nvref::NodeVariableRef)
    gb = graph_backend(nvref.node)
    ci = MOI.ConstraintIndex{MOI.VariableIndex,MOI.EqualTo{Float64}}(
        gb.element_to_graph_map[nvref].value
    )
    cref = gb.graph_to_element_map[ci]
    return cref
end

# get/set variable bounds

function _moi_nv_has_upper_bound(nvref::NodeVariableRef)
    gb = graph_backend(nvref.node)
    ci = MOI.ConstraintIndex{MOI.VariableIndex,MOI.LessThan{Float64}}(
        gb.element_to_graph_map[nvref].value
    )
    return MOI.is_valid(graph_backend(nvref.node), ci)
end

function _nv_upper_bound_ref(nvref::NodeVariableRef)
    gb = graph_backend(nvref.node)
    ci = MOI.ConstraintIndex{MOI.VariableIndex,MOI.LessThan{Float64}}(
        gb.element_to_graph_map[nvref].value
    )
    cref = gb.graph_to_element_map[ci]
    return cref
end

function _moi_nv_has_lower_bound(nvref::NodeVariableRef)
    gb = graph_backend(nvref.node)
    ci = MOI.ConstraintIndex{MOI.VariableIndex,MOI.GreaterThan{Float64}}(
        gb.element_to_graph_map[nvref].value
    )
    return MOI.is_valid(graph_backend(nvref.node), ci)
end

function _nv_lower_bound_ref(nvref::NodeVariableRef)
    gb = graph_backend(nvref.node)
    ci = MOI.ConstraintIndex{MOI.VariableIndex,MOI.GreaterThan{Float64}}(
        gb.element_to_graph_map[nvref].value
    )
    cref = gb.graph_to_element_map[ci]
    return cref
end

### Constraints

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
        # update func variable indices
        moi_func_graph = _create_graph_moi_func(graph_backend(graph), moi_func, jump_func)

        # add contraint to backend
        _add_element_constraint_to_backend(
            graph_backend(graph), 
            cref, 
            moi_func_graph, 
            moi_set
        )
    end
    return cref
end

function next_constraint_index(
    edge::OptiEdge, 
    ::Type{F}, 
    ::Type{S}
)::MOI.ConstraintIndex{F,S} where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    index = num_constraints(edge, F, S)
    return MOI.ConstraintIndex{F,S}(index + 1)
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
        moi_func_graph = _create_graph_moi_func(graph_backend(graph), moi_func, jump_func)

        # add the constraint to the backend
        _add_element_constraint_to_backend(
            graph_backend(graph), 
            cref, 
            moi_func_graph, 
            moi_set
        )
    end
    return cref
end

function _add_element_constraint_to_backend(
    graph_backend::GraphMOIBackend,
    cref::ConstraintRef,
    func::F,
    set::S
) where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    cref in keys(graph_backend.element_to_graph_map.con_map) && return
    if !haskey(graph_backend.element_constraints, cref.model)
        graph_backend.element_constraints[cref.model] = MOI.ConstraintIndex[]
    end
    graph_con_index = MOI.add_constraint(graph_backend.moi_backend, func, set)
    graph_backend.element_to_graph_map[cref] = graph_con_index
    graph_backend.graph_to_element_map[graph_con_index] = cref
    push!(graph_backend.element_constraints[cref.model], graph_con_index)
    return graph_con_index
end

### Graph MOI Utilities

"""
    _create_graph_moi_func(
        backend::GraphMOIBackend,
        moi_func::MOI.VariableIndex,
        jump_func::NodeVariableRef
    )

Create an MOI function with the actual variable indices from a backend graph.
"""
function _create_graph_moi_func(
    backend::GraphMOIBackend,
    moi_func::MOI.VariableIndex,
    jump_func::NodeVariableRef
)
    return backend.element_to_graph_map[jump_func]
end

"""
    _create_graph_moi_func(
        backend::GraphMOIBackend,
        moi_func::MOI.ScalarAffineFunction,
        jump_func::JuMP.GenericAffExpr
    )

Create an MOI function with the actual variable indices from a backend graph.
"""
function _create_graph_moi_func(
    backend::GraphMOIBackend,
    moi_func::MOI.ScalarAffineFunction,
    jump_func::JuMP.GenericAffExpr
)
    moi_func_graph = deepcopy(moi_func)
    for (i, term) in enumerate(JuMP.linear_terms(jump_func))
        coeff = term[1]
        var = term[2]
        backend_var_idx = backend.element_to_graph_map[var]
        moi_func_graph.terms[i] = MOI.ScalarAffineTerm{Float64}(coeff, backend_var_idx)
    end
    return moi_func_graph
end

function _create_graph_moi_func(
    backend::GraphMOIBackend,
    moi_func::MOI.ScalarQuadraticFunction,
    jump_func::JuMP.GenericQuadExpr
)
    moi_func_graph = deepcopy(moi_func)
    #quadratic terms
    for (i, term) in enumerate(JuMP.quad_terms(jump_func))
        coeff = term[1]
        var1 = term[2]
        var2 = term[3]
        var_idx_1 = backend.element_to_graph_map[var1]
        var_idx_2 = backend.element_to_graph_map[var2]

        moi_func_graph.quadratic_terms[i] = MOI.ScalarQuadraticTerm{Float64}(
            coeff, 
            var_idx_1, 
            var_idx_2
        )
    end

    # linear terms
    for (i, term) in enumerate(JuMP.linear_terms(jump_func))
        coeff = term[1]
        var = term[2]
        backend_var_idx = backend.element_to_graph_map[var]
        moi_func_graph.affine_terms[i] = MOI.ScalarAffineTerm{Float64}(coeff, backend_var_idx)
    end
    return moi_func_graph
end

function _create_graph_moi_func(
    backend::GraphMOIBackend,
    moi_func::MOI.ScalarNonlinearFunction,
    jump_func::JuMP.GenericNonlinearExpr
)
    moi_func_graph = deepcopy(moi_func)
    _update_nonlinear_func!(backend, moi_func_graph, jump_func)
    return moi_func_graph
end

function _update_nonlinear_func!(
    backend::GraphMOIBackend,
    moi_func::MOI.ScalarNonlinearFunction,
    jump_func::JuMP.GenericNonlinearExpr
)
    for i = 1:length(jump_func.args)
        jump_arg = jump_func.args[i]
        moi_arg = moi_func.args[i]
        if jump_arg isa JuMP.GenericNonlinearExpr
            _update_nonlinear_func!(backend, moi_arg, jump_arg)
        elseif typeof(jump_arg) == NodeVariableRef
            moi_func.args[i] = backend.element_to_graph_map[jump_arg]
        end
    end
    return
end

# add variables to a backend for linking across subgraphs
function _add_backend_variables(
    backend::GraphMOIBackend,
    jump_func::JuMP.GenericAffExpr
)
    vars = [term[2] for term in JuMP.linear_terms(jump_func)]
    vars_to_add = setdiff(vars, keys(backend.element_to_graph_map.var_map))
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
    vars_to_add = setdiff(vars_unique, keys(backend.element_to_graph_map.var_map))
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
    vars_to_add = setdiff(vars, keys(backend.element_to_graph_map.var_map))
    for var in vars_to_add
        _add_variable_to_backend(backend, var)
    end
    return
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
    _create_graph_moi_func(graph_backend(graph), moi_func, expr)

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
    _create_graph_moi_func(graph_backend(graph), moi_func, expr)

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
    _create_graph_moi_func(graph_backend(graph), moi_func, expr)

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
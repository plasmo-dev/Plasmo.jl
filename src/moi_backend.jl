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

# MOI Interface

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

function MOI.optimize!(gb::GraphMOIBackend)
    MOI.optimize!(gb.moi_backend)
    return nothing
end

### Variables and Constraints

function next_variable_index(node::OptiNode)
    return MOI.VariableIndex(JuMP.num_variables(node) + 1)
end

function graph_index(gb::GraphMOIBackend, nvref::NodeVariableRef)
    return gb.element_to_graph_map[nvref]
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
    #println("cref to add: ", cref)
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
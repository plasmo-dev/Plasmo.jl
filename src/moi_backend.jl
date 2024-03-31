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
    optigraph::OptiGraph
    moi_backend::MOI.AbstractOptimizer
    
    element_to_graph_map::ElementToGraphMap
    graph_to_element_map::GraphToElementMap

    # map of variables and constraints on nodes and edges to graph backend indices
    node_variables::OrderedDict{OptiNode,Vector{MOI.VariableIndex}}
    element_constraints::OrderedDict{OptiElement,Vector{MOI.ConstraintIndex}}
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

function _add_node(gb::GraphMOIBackend, node::OptiNode)
    gb.node_variables[node] = MOI.VariableIndex[]
    gb.element_constraints[node] = MOI.ConstraintIndex[]
end

function _add_edge(gb::GraphMOIBackend, edge::OptiEdge)
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
    return
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

        # TODO: debug why i have to do this; the coeff is 1, but it prints as 2
        if var1 == var2
            coeff *= 2
        end

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
        moi_func_graph.affine_terms[i] = MOI.ScalarAffineTerm{Float64}(
            coeff, 
            backend_var_idx
        )
    end
    return moi_func_graph
end

function _create_graph_moi_func(
    backend::GraphMOIBackend,
    moi_func::MOI.ScalarNonlinearFunction,
    jump_func::JuMP.GenericNonlinearExpr
)
    moi_func_graph = deepcopy(moi_func)
    for i = 1:length(jump_func.args)
        jump_arg = jump_func.args[i]
        moi_arg = moi_func.args[i]
        if jump_arg isa Number
            continue
        elseif typeof(jump_arg) == NodeVariableRef
            moi_func_graph.args[i] = backend.element_to_graph_map[jump_arg]
        else
            new_func = _create_graph_moi_func(backend, moi_arg, jump_arg)
            moi_func_graph.args[i] = new_func
        end
    end
    #_update_nonlinear_func!(backend, moi_func_graph, jump_func)
    return moi_func_graph
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

### Aggregate MOI backends

"""
    aggregate_backends!(graph::OptiGraph)

Aggregate the moi backends from each subgraph within `graph` to create a single backend.
"""
function aggregate_backends!(graph::OptiGraph)
    for subgraph in get_subgraphs(graph)
        _copy_subgraph_nodes!(graph, subgraph)
        _copy_subgraph_edges!(graph, subgraph)
        # TODO: pass non-objective graph attributes (use an MOI Filter?)
    end
end

function _copy_subgraph_nodes!(graph::OptiGraph, subgraph::OptiGraph)
    for node in all_nodes(subgraph)
        _append_node_to_backend!(graph, node)
    end
end

function _copy_subgraph_edges!(graph::OptiGraph, subgraph::OptiGraph)
    for edge in all_edges(subgraph)
        _append_edge_to_backend!(graph, edge)
    end
end

function _append_node_to_backend!(graph::OptiGraph, node::OptiNode)
    _add_node(graph_backend(graph), node)
    source = source_graph(node)
    if haskey(source.node_to_graphs, node)
        push!(source.node_to_graphs[node], graph)
    else
        source.node_to_graphs[node] = [graph]
    end


    src = graph_backend(node)
    dest = graph_backend(graph)
    index_map = MOIU.IndexMap()

    # copy node variables and variable attributes
    _copy_node_variables(dest, node, index_map)

    # copy constraints and constraint attributes
    # NOTE: for now, we split between variable and non-variable, but they do the same thing.
    # eventually, we might try doing something more similar to MOI `default_copy_to` where
    # we try to constrain variables on creation.
    all_constraint_types = MOI.get(node, MOI.ListOfConstraintTypesPresent())
    variable_constraint_types = filter(all_constraint_types) do (F, S)
        return MOIU._is_variable_function(F)
    end
    _copy_element_constraints(
        dest, 
        node,
        index_map, 
        variable_constraint_types
    )

    # copy non-variable constraints
    nonvariable_constraint_types = filter(all_constraint_types) do (F, S)
        return !MOIU._is_variable_function(F)
    end
    _copy_element_constraints(
        dest,
        node,
        index_map,
        nonvariable_constraint_types
    )
    return
end

function _copy_node_variables(
    dest::GraphMOIBackend,
    node::OptiNode,
    index_map::MOIU.IndexMap
)
    src = graph_backend(node)
    node_variables = all_variables(node)

    # map existing variables in index_map
    existing_vars = intersect(node_variables, keys(dest.element_to_graph_map.var_map))
    for var in existing_vars
        src_graph_index = graph_index(var)
        dest_graph_index = dest.element_to_graph_map[var]
        index_map[src_graph_index] = dest_graph_index
    end

    # create and add new variables
    vars_to_add = setdiff(node_variables, keys(dest.element_to_graph_map.var_map))
    for var in vars_to_add
        src_graph_index = graph_index(var)
        dest_graph_index = _add_variable_to_backend(dest, var)
        index_map[src_graph_index] = dest_graph_index
    end

    # pass variable attributes
    vis_src = graph_index.(node_variables)
    MOIU.pass_attributes(dest.moi_backend, src.moi_backend, index_map, vis_src)
    return
end

function _copy_element_constraints(
    dest::GraphMOIBackend, 
    element::OptiElement,
    index_map::MOIU.IndexMap,
    constraint_types
)
    for (F, S) in constraint_types
        cis_src = MOI.get(element, MOI.ListOfConstraintIndices{F,S}())
        _copy_element_constraints(dest, element, index_map, cis_src)
    end
    
    # pass constraint attributes
    src = graph_backend(element)
    for (F, S) in constraint_types
        MOIU.pass_attributes(
            dest.moi_backend,
            src.moi_backend,
            index_map,
            MOI.get(element, MOI.ListOfConstraintIndices{F,S}()),
        )
    end
    return
end

function _copy_element_constraints(
    dest::GraphMOIBackend, 
    element::OptiElement, 
    index_map::MOIU.IndexMap, 
    cis_src::Vector{MOI.ConstraintIndex{F,S}}
) where {F,S}
    return _copy_element_constraints(dest, element, index_map, index_map[F, S], cis_src)
end

function _copy_element_constraints(
    dest::GraphMOIBackend,
    element::OptiElement,
    index_map::MOIU.IndexMap,
    index_map_FS,
    cis_src::Vector{<:MOI.ConstraintIndex},
)
    src = graph_backend(element)
    for ci in cis_src
        f = MOI.get(src.moi_backend, MOI.ConstraintFunction(), ci)
        s = MOI.get(src.moi_backend, MOI.ConstraintSet(), ci)
        cref = src.graph_to_element_map[ci]
        cref in keys(dest.element_to_graph_map.con_map) && return
        dest_index = _add_element_constraint_to_backend(
            dest,
            cref,
            MOIU.map_indices(index_map, f), 
            s
        )
        index_map_FS[ci] = dest_index
    end
    return
end

function _append_edge_to_backend!(graph::OptiGraph, edge::OptiEdge)
    _add_edge(graph_backend(graph), edge)
    source = source_graph(edge)
    if haskey(source.edge_to_graphs, edge)
        push!(source.edge_to_graphs[edge], graph)
    else
        source.edge_to_graphs[edge] = [graph]
    end
    
    src = graph_backend(edge)
    dest = graph_backend(graph)

    # populate index map with node data for src -- > dest
    index_map = MOIU.IndexMap()
    vars = all_variables(edge)
    for var in vars
        index_map[src.element_to_graph_map[var]] = dest.element_to_graph_map[var]
    end

    # copy the constraints
    constraint_types = MOI.get(edge, MOI.ListOfConstraintTypesPresent())
    _copy_element_constraints(
        dest,
        edge,
        index_map,
        constraint_types
    )
    return
end
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

function Base.setindex!(
    n2g_map::ElementToGraphMap, idx::MOI.VariableIndex, vref::NodeVariableRef
)
    n2g_map.var_map[vref] = idx
    return nothing
end

function Base.getindex(n2g_map::ElementToGraphMap, vref::NodeVariableRef)
    return n2g_map.var_map[vref]
end

function Base.setindex!(
    n2g_map::ElementToGraphMap, idx::MOI.ConstraintIndex, cref::ConstraintRef
)
    n2g_map.con_map[cref] = idx
    return nothing
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

function Base.setindex!(
    g2element_map::GraphToElementMap, vref::NodeVariableRef, idx::MOI.VariableIndex
)
    g2element_map.var_map[idx] = vref
    return nothing
end

function Base.getindex(g2element_map::GraphToElementMap, idx::MOI.VariableIndex)
    return g2element_map.var_map[idx]
end

function Base.setindex!(
    g2element_map::GraphToElementMap, cref::ConstraintRef, idx::MOI.ConstraintIndex
)
    g2element_map.con_map[idx] = cref
    return nothing
end

function Base.getindex(g2element_map::GraphToElementMap, idx::MOI.ConstraintIndex)
    return g2element_map.con_map[idx]
end

"""
    GraphMOIBackend

Acts as an intermediate optimization layer. It maps graph elements to an MOI optimizer.
The backend does not yet support more than a CachingOptimizer. We intend to
support Direct, Manual, and Automatic modes just like JuMP at some point.
"""
mutable struct GraphMOIBackend <: MOI.AbstractOptimizer
    optigraph::OptiGraph
    moi_backend::MOI.AbstractOptimizer

    # maintain two-way between graph and element indices
    element_to_graph_map::ElementToGraphMap
    graph_to_element_map::GraphToElementMap

    # map of nodes and edges to variables and constraints.
    node_variables::OrderedDict{OptiNode,Vector{MOI.VariableIndex}}
    element_constraints::OrderedDict{OptiElement,Vector{MOI.ConstraintIndex}}
    element_attributes::OrderedDict{Tuple{OptiElement,MOI.AbstractModelAttribute},Any}
    operator_map::OrderedDict{Tuple{OptiElement,Symbol},Symbol}
end

"""
    GraphMOIBackend(graph::OptiGraph)

Initialize an empty backend given an optigraph.
By default we use a `CachingOptimizer` to store the underlying optimizer just like JuMP.
"""
function GraphMOIBackend(graph::OptiGraph)
    inner = MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}())
    cache = MOI.Utilities.CachingOptimizer(inner, MOI.Utilities.AUTOMATIC)
    return GraphMOIBackend(
        graph,
        cache,
        ElementToGraphMap(),
        GraphToElementMap(),
        OrderedDict{OptiNode,Vector{MOI.VariableIndex}}(),
        OrderedDict{OptiElement,Vector{MOI.ConstraintIndex}}(),
        OrderedDict{Tuple{OptiElement,MOI.AbstractModelAttribute},Any}(),
        OrderedDict{Tuple{OptiElement,Symbol},Symbol}(),
    )
end

function graph_index(
    backend::GraphMOIBackend, ref::RT
) where {RT<:Union{NodeVariableRef,ConstraintRef}}
    return backend.element_to_graph_map[ref]
end

# JuMP Methods

function JuMP.backend(backend::GraphMOIBackend)
    return backend.moi_backend
end

function JuMP.set_optimizer(backend::GraphMOIBackend, optimizer)
    return backend.moi_backend = MOIU.CachingOptimizer(
        backend.moi_backend.model_cache, optimizer
    )
end

function JuMP.constraint_ref_with_index(backend::GraphMOIBackend, idx::MOI.Index)
    return backend.graph_to_element_map[idx]
end

"""
    graph_operator(backend::GraphMOIBackend, element::OptiElement, name::Symbol)

Return the name of the registered nonlinear operator in the graph backend 
corresponding to the name in the element. 
"""
function graph_operator(backend::GraphMOIBackend, element::OptiElement, name::Symbol)
    return backend.operator_map[(element, name)]
end

function add_node(backend::GraphMOIBackend, node::OptiNode)
    _add_node(backend, node)
    # if adding an existing node from another graph, we need to copy model attributes
    if source_graph(node) != backend.optigraph
        _copy_node_to_backend!(backend, node)
    end
    return nothing
end

function _add_node(backend::GraphMOIBackend, node::OptiNode)
    if !haskey(backend.node_variables, node)
        backend.node_variables[node] = MOI.VariableIndex[]
    end
    if !haskey(backend.element_constraints, node)
        backend.element_constraints[node] = MOI.ConstraintIndex[]
    end
    return nothing
end

function add_edge(backend::GraphMOIBackend, edge::OptiEdge)
    _add_edge(backend, edge)
    # if adding an existing edge from another graph, we need to copy model attributes
    if source_graph(edge) != backend.optigraph
        _copy_edge_to_backend!(backend, edge)
    end
    return nothing
end

function _add_edge(backend::GraphMOIBackend, edge::OptiEdge)
    if !haskey(backend.element_constraints, edge)
        backend.element_constraints[edge] = MOI.ConstraintIndex[]
    end
    return nothing
end

#
# MOI Methods
#

### graph attributes

function MOI.get(
    backend::GraphMOIBackend, attr::AT
) where {AT<:Union{MOI.AbstractModelAttribute,MOI.AbstractOptimizerAttribute}}
    return MOI.get(backend.moi_backend, attr)
end

function MOI.set(
    backend::GraphMOIBackend, attr::AT, args...
) where {AT<:Union{MOI.AbstractModelAttribute,MOI.AbstractOptimizerAttribute}}
    MOI.set(backend.moi_backend, attr, args...)
    return nothing
end

# element attributes

# By default, just try to get the attribute from the graph MOI backend
function MOI.get(backend::GraphMOIBackend, attr::MOI.AnyAttribute, element::OptiElement)
    return MOI.get(backend.moi_backend, attr)
end

function MOI.get(backend::GraphMOIBackend, attr::MOI.NumberOfVariables, node::OptiNode)
    return length(backend.node_variables[node])
end

function MOI.get(
    backend::GraphMOIBackend, attr::MOI.ListOfConstraintTypesPresent, element::OptiElement
)
    cons = backend.element_constraints[element]
    con_types = unique(typeof.(cons))
    type_tuple = [(type.parameters[1], type.parameters[2]) for type in con_types]
    return type_tuple
end

function MOI.get(
    backend::GraphMOIBackend, attr::MOI.ListOfConstraintIndices{F,S}, element::OptiElement
) where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    con_inds = MOI.ConstraintIndex{F,S}[]
    for con in backend.element_constraints[element]
        if (typeof(con).parameters[1] == F && typeof(con).parameters[2] == S)
            push!(con_inds, con)
        end
    end
    return con_inds
end

function MOI.get(
    backend::GraphMOIBackend, attr::MOI.NumberOfConstraints{F,S}, element::OptiElement
) where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    # filter F and S
    n_cons = 0
    for con in backend.element_constraints[element]
        if (typeof(con).parameters[1] == F && typeof(con).parameters[2] == S)
            n_cons += 1
        end
    end
    return n_cons
end

function MOI.set(
    backend::GraphMOIBackend, attr::MOI.UserDefinedFunction, node::OptiNode, args...
)
    registered_name = Symbol(node.label, ".", attr.name)
    MOI.set(
        backend.moi_backend, MOI.UserDefinedFunction(registered_name, attr.arity), args...
    )
    backend.element_attributes[(node, attr)] = tuple(args...)
    return backend.operator_map[(node, attr.name)] = registered_name
end

### variable attributes

function MOI.get(
    backend::GraphMOIBackend, attr::AT, nvref::NodeVariableRef
) where {AT<:MOI.AbstractVariableAttribute}
    graph_index = backend.element_to_graph_map[nvref]
    return MOI.get(backend.moi_backend, attr, graph_index)
end

function MOI.set(
    backend::GraphMOIBackend, attr::AT, nvref::NodeVariableRef, args...
) where {AT<:MOI.AbstractVariableAttribute}
    graph_index = backend.element_to_graph_map[nvref]
    MOI.set(backend.moi_backend, attr, graph_index, args...)
    return nothing
end

### constraint attributes

function MOI.get(
    backend::GraphMOIBackend, attr::AT, cref::ConstraintRef
) where {AT<:MOI.AbstractConstraintAttribute}
    graph_index = backend.element_to_graph_map[cref]
    return MOI.get(backend.moi_backend, attr, graph_index)
end

function MOI.set(
    backend::GraphMOIBackend, attr::AT, cref::ConstraintRef, args...
) where {AT<:MOI.AbstractConstraintAttribute}
    graph_index = backend.element_to_graph_map[cref]
    return MOI.set(backend.moi_backend, attr, graph_index, args...)
end

# modify

function MOI.modify(
    backend::GraphMOIBackend,
    attr::MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}},
    variable::NodeVariableRef,
    coeff::Float64,
)
    return MOI.modify(
        backend.moi_backend,
        attr,
        MOI.ScalarCoefficientChange(graph_index(backend, variable), coeff),
    )
end

function MOI.modify(
    backend::GraphMOIBackend,
    attr::MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}},
    variables::AbstractVector{<:NodeVariableRef},
    coeffs::AbstractVector{<:Float64},
)
    return MOI.modify(
        backend.moi_backend,
        attr,
        MOI.ScalarCoefficientChange.(graph_index.(Ref(backend), variables), coeffs),
    )
end

function MOI.modify(
    backend::GraphMOIBackend,
    attr::MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}},
    variable_1::NodeVariableRef,
    variable_2::NodeVariableRef,
    coeff::Float64,
)
    return MOI.modify(
        backend.moi_backend,
        attr,
        MOI.ScalarQuadraticCoefficientChange(
            graph_index(backend, variable_1), graph_index(backend, variable_2), coeff
        ),
    )
end

function MOI.modify(
    backend::GraphMOIBackend,
    attr::MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}},
    variables_1::AbstractVector{<:NodeVariableRef},
    variables_2::AbstractVector{<:NodeVariableRef},
    coeffs::AbstractVector{<:Float64},
)
    return MOI.modify(
        backend.moi_backend,
        attr,
        MOI.ScalarQuadraticCoefficientChange.(
            graph_index.(backend, variables_1), graph_index.(backend, variables_2), coeffs
        ),
    )
end

### delete

function MOI.delete(backend::GraphMOIBackend, nvref::NodeVariableRef)
    index = backend.element_to_graph_map[nvref]
    MOI.delete(backend.moi_backend, index)

    # delete from list
    list_index = findall(x -> x == index, backend.node_variables[nvref.node])
    deleteat!(backend.node_variables[nvref.node], list_index)

    # delete dictionary entries
    delete!(backend.graph_to_element_map.var_map, backend.element_to_graph_map[nvref])
    delete!(backend.element_to_graph_map.var_map, nvref)
    return nothing
end

function MOI.delete(backend::GraphMOIBackend, cref::ConstraintRef)
    # delete backend index
    index = backend.element_to_graph_map[cref]
    MOI.delete(backend.moi_backend, index)

    # delete from list
    list_index = findall(x -> x == index, backend.element_constraints[cref.model])
    deleteat!(backend.element_constraints[cref.model], list_index)

    # delete dicionary entries
    delete!(backend.graph_to_element_map.con_map, backend.element_to_graph_map[cref])
    delete!(backend.element_to_graph_map.con_map, cref)

    return nothing
end

### is_valid

function MOI.is_valid(backend::GraphMOIBackend, vref::NodeVariableRef)
    return MOI.is_valid(backend.moi_backend, graph_index(vref))
end

function MOI.is_valid(backend::GraphMOIBackend, cref::ConstraintRef)
    return MOI.is_valid(backend.moi_backend, graph_index(cref))
end

function MOI.is_valid(backend::GraphMOIBackend, vi::MOI.VariableIndex)
    return MOI.is_valid(backend.moi_backend, vi)
end

function MOI.is_valid(backend::GraphMOIBackend, ci::MOI.ConstraintIndex)
    return MOI.is_valid(backend.moi_backend, ci)
end

### optimize!

function MOI.optimize!(backend::GraphMOIBackend)
    # If there are subgraphs, we need to copy their backend data to this graph
    _copy_subgraph_backends!(backend)
    MOI.optimize!(backend.moi_backend)
    return nothing
end

#
# MOI cariables and constraints
#

function MOI.add_variable(graph_backend::GraphMOIBackend, vref::NodeVariableRef)
    # return if variable already exists in backend
    vref in keys(graph_backend.element_to_graph_map.var_map) && return nothing

    # add the variable
    graph_var_index = MOI.add_variable(graph_backend.moi_backend)

    # map reference to index
    graph_backend.element_to_graph_map[vref] = graph_var_index
    graph_backend.graph_to_element_map[graph_var_index] = vref

    # create key for node if necessary
    if !haskey(graph_backend.node_variables, vref.node)
        graph_backend.node_variables[vref.node] = MOI.VariableIndex[]
    end
    push!(graph_backend.node_variables[vref.node], graph_var_index)
    return graph_var_index
end

function MOI.add_constraint(
    backend::GraphMOIBackend,
    cref::ConstraintRef,
    moi_func::F,
    moi_set::S;
    add_variables=false,
) where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    # return if reference already mapped to element
    cref in keys(backend.element_to_graph_map.con_map) && return nothing

    # create key for element if necessary
    if !haskey(backend.element_constraints, cref.model)
        graph_backend.element_constraints[cref.model] = MOI.ConstraintIndex[]
    end

    # create the constraint
    graph_con_index = MOI.add_constraint(backend.moi_backend, moi_func, moi_set)

    # map reference to index
    backend.element_to_graph_map[cref] = graph_con_index
    backend.graph_to_element_map[graph_con_index] = cref

    # add index to element map
    push!(backend.element_constraints[cref.model], graph_con_index)
    return graph_con_index
end

function MOI.add_constraint(
    backend::GraphMOIBackend,
    cref::ConstraintRef,
    jump_func::F,
    moi_set::S;
    add_variables=false,
) where {F<:JuMP.AbstractJuMPScalar,S<:MOI.AbstractSet}
    # add backend variables if necessary (such as adding links across graphs)
    if add_variables
        _add_backend_variables(backend, jump_func)
    end

    # assemble MOI function for graph backend
    moi_func = JuMP.moi_function(jump_func)
    moi_func_graph = _create_graph_moi_func(backend, moi_func, jump_func)
    return MOI.add_constraint(
        backend, cref, moi_func_graph, moi_set; add_variables=add_variables
    )
end

#
# Graph MOI Utilities
#

# NOTE: These utilities are meant to take model expressions defined over optinodes and 
# map them to the underlying optigraph backend indices. This way, nodes and edges
# can be mapped to multiple possible optigraph backends.

function _create_graph_moi_func end
"""
    _create_graph_moi_func(
        backend::GraphMOIBackend,
        moi_func::MOI.VariableIndex,
        jump_func::NodeVariableRef
    )
    _create_graph_moi_func(
        backend::GraphMOIBackend,
        moi_func::MOI.ScalarAffineFunction,
        jump_func::JuMP.GenericAffExpr
    )
    _create_graph_moi_func(
        backend::GraphMOIBackend,
        moi_func::MOI.ScalarQuadraticFunction,
        jump_func::JuMP.GenericQuadExpr
    )
    _create_graph_moi_func(
        backend::GraphMOIBackend,
        moi_func::MOI.ScalarNonlinearFunction,
        jump_func::JuMP.GenericNonlinearExpr
    )

Create an MOI function with true variable indices from a backend graph. This utility 
function swaps out the `moi_func` terms (which are local to optinodes) using the node 
variables in `jump_func` that map to graph variable indices in the graph backend.

Parameters
----------
backend: the backend model for an optigraph.
moi_func: an MOI function defined over node variable indices.
jump_func: a JuMP expression defined with `NodeVariableRef`s.
"""

function _create_graph_moi_func(
    backend::GraphMOIBackend, moi_func::MOI.VariableIndex, jump_func::NodeVariableRef
)
    return backend.element_to_graph_map[jump_func]
end

function _create_graph_moi_func(
    backend::GraphMOIBackend,
    moi_func::MOI.ScalarAffineFunction,
    jump_func::JuMP.GenericAffExpr,
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
    jump_func::JuMP.GenericQuadExpr,
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
            coeff, var_idx_1, var_idx_2
        )
    end

    # linear terms
    for (i, term) in enumerate(JuMP.linear_terms(jump_func))
        coeff = term[1]
        var = term[2]
        backend_var_idx = backend.element_to_graph_map[var]
        moi_func_graph.affine_terms[i] = MOI.ScalarAffineTerm{Float64}(
            coeff, backend_var_idx
        )
    end
    return moi_func_graph
end

function _create_graph_moi_func(
    backend::GraphMOIBackend,
    moi_func::MOI.ScalarNonlinearFunction,
    jump_func::JuMP.GenericNonlinearExpr,
)
    moi_func_graph = deepcopy(moi_func)
    for i in 1:length(jump_func.args)
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
    return moi_func_graph
end

### _add_backend_variables

function _add_backend_variables(backend::GraphMOIBackend, var::NodeVariableRef)
    vars = [var]
    _add_backend_variables(backend, vars)
    return nothing
end

function _add_backend_variables(backend::GraphMOIBackend, vars::Vector{NodeVariableRef})
    vars_to_add = setdiff(vars, keys(backend.element_to_graph_map.var_map))
    for var in vars_to_add
        # _add_variable_to_backend(backend, var)
        MOI.add_variable(backend, var)
    end
    return nothing
end

function _add_backend_variables(backend::GraphMOIBackend, jump_func::JuMP.GenericAffExpr)
    # add variables to a backend for linking across subgraphs
    vars = [term[2] for term in JuMP.linear_terms(jump_func)]
    _add_backend_variables(backend, vars)
    return nothing
end

function _add_backend_variables(backend::GraphMOIBackend, jump_func::JuMP.GenericQuadExpr)
    vars_aff = [term[2] for term in JuMP.linear_terms(jump_func)]
    vars_quad = vcat([[term[2], term[3]] for term in JuMP.quad_terms(jump_func)]...)
    vars_unique = unique([vars_aff; vars_quad])
    _add_backend_variables(backend, vars_unique)
    return nothing
end

function _add_backend_variables(
    backend::GraphMOIBackend, jump_func::JuMP.GenericNonlinearExpr
)
    vars = NodeVariableRef[]
    for i in 1:length(jump_func.args)
        jump_arg = jump_func.args[i]
        if typeof(jump_arg) == JuMP.GenericNonlinearExpr
            _add_backend_variables(backend, jump_arg)
        elseif typeof(jump_arg) == NodeVariableRef
            push!(vars, jump_arg)
        end
    end
    _add_backend_variables(backend, vars)
    return nothing
end

#
# Aggregate MOI backends
#

# Note that these methods do not create copies of nodes or edges; they create model 
# data for new backends. The nodes and edges will then reference data for multiple backends. 

"""
    _copy_subgraph_backends!(graph::OptiGraph)

Aggregate the moi backends from each subgraph within `graph` to create a single backend.
"""
function _copy_subgraph_backends!(backend::GraphMOIBackend)
    graph = backend.optigraph
    for subgraph in local_subgraphs(graph)
        _copy_subgraph_nodes!(backend, subgraph)
        _copy_subgraph_edges!(backend, subgraph)
        # TODO: pass non-objective graph attributes we may need (use an MOI Filter?)
    end
end

function _copy_subgraph_nodes!(backend::GraphMOIBackend, subgraph::OptiGraph)
    graph = backend.optigraph
    for node in all_nodes(subgraph) # NOTE: hits ALL NODES in the subgraph.
        # check to make sure we are not copying again
        # TODO: check the backend state, not the containing_optigraphs
        if !(graph in containing_optigraphs(node))
            _add_node(backend, node)
            _copy_node_to_backend!(backend, node)
        end
    end
end

function _copy_subgraph_edges!(backend::GraphMOIBackend, subgraph::OptiGraph)
    graph = backend.optigraph
    for edge in all_edges(subgraph)
        # check to make sure we are not copying again
        if !(graph in containing_optigraphs(edge))
            _add_edge(backend, edge)
            _copy_edge_to_backend!(backend, edge)
        end
    end
end

function _copy_node_to_backend!(backend::GraphMOIBackend, node::OptiNode)
    dest = backend
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
    _copy_element_constraints(dest, node, index_map, variable_constraint_types)

    # copy non-variable constraints
    nonvariable_constraint_types = filter(all_constraint_types) do (F, S)
        return !MOIU._is_variable_function(F)
    end
    _copy_element_constraints(dest, node, index_map, nonvariable_constraint_types)
    return nothing
end

function _copy_edge_to_backend!(backend::GraphMOIBackend, edge::OptiEdge)
    src = graph_backend(edge)
    dest = backend

    # add variables in cases edge connects across subgraphs
    _add_backend_variables(dest, all_variables(edge))

    # populate index map with node data for src -- > dest
    index_map = MOIU.IndexMap()
    vars = all_variables(edge)
    for var in vars
        index_map[src.element_to_graph_map[var]] = dest.element_to_graph_map[var]
    end

    # copy the constraints
    constraint_types = MOI.get(edge, MOI.ListOfConstraintTypesPresent())
    _copy_element_constraints(dest, edge, index_map, constraint_types)
    return nothing
end

function _copy_node_variables(
    dest::GraphMOIBackend, node::OptiNode, index_map::MOIU.IndexMap
)
    src = graph_backend(node)
    node_variables = all_variables(node)

    # map existing variables in the index_map
    # existing variables may come from linking constraints added between graphs
    existing_vars = intersect(node_variables, keys(dest.element_to_graph_map.var_map))
    for var in existing_vars
        src_graph_index = graph_index(var)
        dest_graph_index = dest.element_to_graph_map[var]
        index_map[src_graph_index] = dest_graph_index
    end

    # add new MOI variables to the destination MOI backend
    # note that existing node variables are not copied per-se; the references
    # now point to multiple MOI backends.
    vars_to_add = setdiff(node_variables, keys(dest.element_to_graph_map.var_map))
    for var in vars_to_add
        src_graph_index = graph_index(var)
        #dest_graph_index = _add_variable_to_backend(dest, var)
        dest_graph_index = MOI.add_variable(dest, var)
        index_map[src_graph_index] = dest_graph_index
    end

    # pass variable attributes
    vis_src = graph_index.(node_variables)
    MOIU.pass_attributes(dest.moi_backend, src.moi_backend, index_map, vis_src)
    return nothing
end

function _copy_element_constraints(
    dest::GraphMOIBackend, element::OptiElement, index_map::MOIU.IndexMap, constraint_types
)
    # copy constraints over
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
    return nothing
end

function _copy_element_constraints(
    dest::GraphMOIBackend,
    element::OptiElement,
    index_map::MOIU.IndexMap,
    cis_src::Vector{MOI.ConstraintIndex{F,S}},
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
        # avoid creating duplicate constraints if destination already has reference
        cref = src.graph_to_element_map[ci]
        cref in keys(dest.element_to_graph_map.con_map) && return nothing

        # add constraint
        func = MOI.get(src.moi_backend, MOI.ConstraintFunction(), ci)
        set = MOI.get(src.moi_backend, MOI.ConstraintSet(), ci)
        dest_index = MOI.add_constraint(dest, cref, MOIU.map_indices(index_map, func), set)

        # update index_map
        index_map_FS[ci] = dest_index
    end
    return nothing
end

struct NodeIndex
    value::Int
end

struct OptiNode{GT<:AbstractOptiGraph} <: JuMP.AbstractModel
    source_graph::GT
    idx::NodeIndex
    label::Symbol
end

function Base.string(node::OptiNode)
    return "$(node.label)"
end
Base.print(io::IO, node::OptiNode) = Base.print(io, Base.string(node))
Base.show(io::IO, node::OptiNode) = Base.print(io, node)

function Base.setindex!(node::OptiNode, value::Any, name::Symbol)
    t = (node, name)
    node.source_graph.node_obj_dict[t] = value
    return
end

function Base.getindex(node::OptiNode, name::Symbol)
    t = (node,name)
    return node.source_graph.node_obj_dict[t]
end

function JuMP.num_variables(node::OptiNode)
    return length(graph_backend(node).node_variables[node])
end

function JuMP.all_variables(node::OptiNode)
    gb = graph_backend(node)
    graph_indices = gb.node_variables[node]
    return getindex.(Ref(gb.graph_to_element_map), graph_indices)
end

"""
    graph_backend(node::OptiNode)

Return the `GraphMOIBackend` that holds the associated node model attributes
"""
function graph_backend(node::OptiNode)
    return graph_backend(optimizer_graph(node))
end

"""
    source_graph(node::OptiNode)

Return the optigraph that contains the optinode. This is the optigraph that 
defined said node and stores node object dictionary data.
"""
function source_graph(node::OptiNode)
    return node.source_graph
end

"""
    optimizer_graph(node::OptiNode)

Return the `OptiGraph` that contains the node backend attributes. In most cases, this is the 
same as `source_graph(node)`. For improved performance when modeling with subgraphs, it is 
possible to define all node and edge attributes on a parent graph as opposed to 
the source graph. In this case, `backend_graph(node)` would return said parent graph, 
whereas `source_graph(node)` would return the subgraph.
"""
function optimizer_graph(node::OptiNode)
    return source_graph(node).optimizer_graph
end

function containing_optigraphs(node::OptiNode)
    source = source_graph(node)
    backend_graph = optimizer_graph(node)
    graphs = [backend_graph]
    if haskey(source.node_to_graphs, node)
        graphs = [graphs; source_graph.node_to_graphs[node]]
    end
    return graphs
end

function containing_backends(node::OptiNode)
    return graph_backend.(containing_optigraphs(node))
end

### JuMP Extension

function JuMP.object_dictionary(node::OptiNode)
    return node.source_graph.node_obj_dict
end

function JuMP.backend(node::OptiNode)
    return JuMP.backend(graph_backend(node))
end

function _set_dirty(node::OptiNode)
    for graph in containing_optigraphs(node)
        graph.is_model_dirty = true
    end
    return
end

### OptiNode MOI Extension

# TODO: consider caching constraint types in graph backend versus using unique to filter
function MOI.get(node::OptiNode, attr::MOI.ListOfConstraintTypesPresent)
    cons = graph_backend(node).element_constraints[node]
    con_types = unique(typeof.(cons))
    type_tuple = [(type.parameters[1],type.parameters[2]) for type in con_types]  
    return type_tuple
end

function MOI.get(
    node::OptiNode, 
    attr::MOI.ListOfConstraintIndices{F,S}
) where {F <: MOI.AbstractFunction, S <: MOI.AbstractSet}
    con_inds = MOI.ConstraintIndex{F,S}[]
    for con in graph_backend(node).element_constraints[node]
        if (typeof(con).parameters[1] == F && typeof(con).parameters[2] == S)
            push!(con_inds, con)
        end
    end
    return con_inds
end

# TODO: store objective functions on nodes and query node attributes
# function MOI.get(node::OptiNode, attr::MOI.AnyAttribute)
#     return MOI.get(graph_backend(node), attr)
# end

struct NodeVariableRef <: JuMP.AbstractVariableRef
    node::OptiNode
    index::MOI.VariableIndex
end

function Base.string(vref::NodeVariableRef)
    return JuMP.name(vref)
end
Base.print(io::IO, vref::NodeVariableRef) = Base.print(io, Base.string(vref))
Base.show(io::IO, vref::NodeVariableRef) = Base.print(io, vref)
Base.broadcastable(vref::NodeVariableRef) = Ref(vref)

# Per JuMP comment:
# """
# The default hash is slow. It's important for the performance of AffExpr to
# define our own.
# https://github.com/jump-dev/MathOptInterface.jl/issues/234#issuecomment-366868878
# """
function Base.hash(nvref::NodeVariableRef, h::UInt)
    return hash(objectid(JuMP.owner_model(nvref)), hash(nvref.index.value, h))
end

function Base.isequal(v1::NodeVariableRef, v2::NodeVariableRef)
    return owner_model(v1) === owner_model(v2) && v1.index == v2.index
end

function graph_index(vref::NodeVariableRef)
    return graph_backend(vref.node).element_to_graph_map[vref]
end

function MOI.get(
    node::OptiNode, 
    attr::MOI.AbstractVariableAttribute,
    nvref::NodeVariableRef
)
    return MOI.get(graph_backend(node), attr, graph_index)
end

function MOI.get(
    node::OptiNode, 
    attr::MOI.AbstractConstraintAttribute,
    cref::ConstraintRef
)
    return MOI.get(graph_backend(node), attr, cref)
end

function MOI.set(
    node::OptiNode,
    attr::MOI.AbstractVariableAttribute,
    nvref::NodeVariableRef,  
    args...
)
    for graph in containing_optigraphs(node)
        gb = graph_backend(graph)
        graph_index = gb.element_to_graph_map[nvref]
        MOI.set(gb, attr, graph_index, args...)
    end
    return
end

function MOI.set(
    node::OptiNode,
    attr::MOI.AbstractConstraintAttribute,
    cref::ConstraintRef,
    args...
)
    for graph in containing_optigraphs(JuMP.owner_model(cref))
        graph_index = graph_backend(graph).element_to_graph_map[cref]
        MOI.set(graph_backend(graph), attr, graph_index, args...)
    end
    return
end

function MOI.delete(node::OptiNode, vref::NodeVariableRef)
    for graph in containing_optigraphs(node)
        MOI.delete(graph_backend(graph), vref)
    end
    return
end

function MOI.delete(node::OptiNode, cref::ConstraintRef)
    for graph in containing_optigraphs(node)
        MOI.delete(graph_backend(graph), cref)
    end
    return
end

function JuMP.delete(node::OptiNode, cref::ConstraintRef)
    if node !== JuMP.owner_model(cref)
        error(
            "The constraint reference you are trying to delete does not " *
            "belong to the model.",
        )
    end
    _set_dirty(node)
    MOI.delete(node, cref)
    return
end

### Node Variables

"""
    JuMP.add_variable(node::OptiNode, v::JuMP.AbstractVariable, name::String="")

Add variable `v` to optinode `node`. This function supports use of the `@variable` JuMP macro.
Optionally add a `base_name` to the variable for printing.
"""
function JuMP.add_variable(node::OptiNode, v::JuMP.AbstractVariable, name::String="")
    vref = _moi_add_node_variable(node, v)
    if !isempty(name) && MOI.supports(JuMP.backend(node), MOI.VariableName(), MOI.VariableIndex)
        JuMP.set_name(vref, "$(node.label).$(name)")
    end
    return  vref
end

function _moi_add_node_variable(
    node::OptiNode,
    v::JuMP.AbstractVariable
)
    # get a new variable index and create a reference
    variable_index = next_variable_index(node)
    vref = NodeVariableRef(node, variable_index)

    # add variable to all containing optigraphs
    for graph in containing_optigraphs(node)
        graph_var_index = _add_variable_to_backend(graph_backend(graph), vref)
    end
    # constraint node variable (hits all backends)
    _moi_constrain_node_variable(
        vref,
        v.info, 
        Float64
    )
    return vref
end

function _moi_constrain_node_variable(
    nvref::NodeVariableRef,
    info,
    ::Type{T},
) where {T}
    if info.has_lb
        con = JuMP.ScalarConstraint(nvref, MOI.GreaterThan{T}(info.lower_bound))
        _moi_add_node_constraint(nvref.node, con)
    end
    if info.has_ub
        con = JuMP.ScalarConstraint(nvref, MOI.LessThan{T}(info.upper_bound))
        _moi_add_node_constraint(nvref.node, con)
    end
    if info.has_fix
        con = JuMP.ScalarConstraint(nvref, MOI.EqualTo{T}(info.fixed_value))
        _moi_add_node_constraint(nvref.node, con)
    end
    if info.binary
        con = JuMP.ScalarConstraint(nvref, MOI.ZeroOne())
        _moi_add_node_constraint(nvref.node, con)
    end
    if info.integer
        con = JuMP.ScalarConstraint(nvref, MOI.Integer())
        _moi_add_node_constraint(nvref.node, con)
    end
    if info.has_start && info.start !== nothing
        MOI.set(
            nvref,
            MOI.VariablePrimalStart(),
            convert(T, info.start),
        )
    end
end

function JuMP.delete(node::OptiNode, nvref::NodeVariableRef)
    if node !== JuMP.owner_model(nvref)
        error(
            "The variable reference you are trying to delete does not " *
            "belong to the model.",
        )
    end
    _set_dirty(node)
    for graph in containing_optigraphs(node)
        MOI.delete(graph_backend(node), nvref)
    end
    return
end

function JuMP.is_valid(node::OptiNode, nvref::NodeVariableRef)
    return node === JuMP.owner_model(nvref) &&
           MOI.is_valid(graph_backend(node), nvref)
end

function JuMP.owner_model(nvref::NodeVariableRef)
    return nvref.node
end

function JuMP.name(nvref::NodeVariableRef)
    gb = graph_backend(nvref.node)
    return MOI.get(
        graph_backend(nvref.node), 
        MOI.VariableName(), 
        nvref
    )
end

function JuMP.set_name(nvref::NodeVariableRef, s::String)
    MOI.set(JuMP.owner_model(nvref), MOI.VariableName(), nvref, s)
    return
end

function JuMP.index(vref::NodeVariableRef)
    return vref.index
end

# variable values

function JuMP.value(nvref::NodeVariableRef; result::Int=1)
    return MOI.get(graph_backend(nvref.node), MOI.VariablePrimal(result), nvref)
end

function JuMP.value(var_value::Function, vref::NodeVariableRef)
    return var_value(vref)
end

### node variable bounds

function JuMP.has_lower_bound(nvref::NodeVariableRef)
    return _moi_nv_has_lower_bound(graph_backend(nvref), nvref)
end

function JuMP.set_lower_bound(nvref::NodeVariableRef, lower::Number)
    if !JuMP.isfinite(lower)
        error(
            "Unable to set lower bound to $(lower). To remove the bound, use " *
            "`delete_lower_bound`.",
        )
    end
    _set_dirty(nvref.node)
    _moi_nv_set_lower_bound(nvref, lower)
    return
end

function JuMP.lower_bound(nvref::NodeVariableRef)
    set = MOI.get(JuMP.owner_model(nvref), MOI.ConstraintSet(), JuMP.LowerBoundRef(nvref))
    return set.lower
end

function JuMP.delete_lower_bound(nvref::NodeVariableRef)
    JuMP.delete(JuMP.owner_model(nvref), JuMP.LowerBoundRef(nvref))
    return
end

function JuMP.LowerBoundRef(nvref::NodeVariableRef)
    if !JuMP.has_lower_bound(nvref)
        error("Variable $(nvref) does not have a lower bound.")
    end
    return _nv_lower_bound_ref(nvref)
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

function _moi_nv_set_lower_bound(
    nvref::NodeVariableRef,
    lower::Number,
)
    node = JuMP.owner_model(nvref)
    new_set = MOI.GreaterThan(convert(Float64, lower))
    if _moi_nv_has_lower_bound(nvref)
        cref = _nv_lower_bound_ref(nvref)
        MOI.set(node, MOI.ConstraintSet(), cref, new_set)
    else
        @assert !_moi_nv_is_fixed(nvref)
        con = JuMP.ScalarConstraint(nvref, new_set)
        _moi_add_node_constraint(node, con)
    end
    return
end

function JuMP.has_upper_bound(nvref::NodeVariableRef)
    return _moi_nv_has_upper_bound(graph_backend(nvref), nvref)
end

function JuMP.set_upper_bound(nvref::NodeVariableRef, upper::Number)
    if !JuMP.isfinite(upper)
        error(
            "Unable to set upper bound to $(upper). To remove the bound, use " *
            "`delete_upper_bound`.",
        )
    end
    _set_dirty(nvref.node)
    _moi_nv_set_upper_bound(nvref, upper)
    return
end

function JuMP.delete_upper_bound(nvref::NodeVariableRef)
    JuMP.delete(JuMP.owner_model(nvref), JuMP.LowerBoundRef(nvref))
    return
end

function JuMP.UpperBoundRef(nvref::NodeVariableRef)
    if !JuMP.has_upper_bound(nvref)
        error("Variable $(nvref) does not have an upper bound.")
    end
    return _nv_upper_bound_ref(nvref)
end

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

function _moi_nv_set_upper_bound(
    nvref::NodeVariableRef,
    upper::Number,
)
    node = JuMP.owner_model(nvref)
    new_set = MOI.LessThan(convert(Float64, upper))
    if _moi_nv_has_upper_bound(nvref)
        cref = _nv_upper_bound_ref(nvref)
        MOI.set(node, MOI.ConstraintSet(), cref, new_set)
    else
        @assert !_moi_nv_is_fixed(nvref)
        con = JuMP.ScalarConstraint(nvref, new_set)
        _moi_add_node_constraint(node, con)
    end
    return
end

### fix/unfix variable

function JuMP.FixRef(nvref::NodeVariableRef)
    if !JuMP.is_fixed(nvref)
        error("Variable $(v) does not have fixed bounds.")
    end
    return _nv_fix_ref(nvref)
end

function _nv_fix_ref(nvref::NodeVariableRef)
    gb = graph_backend(nvref.node)
    ci = MOI.ConstraintIndex{MOI.VariableIndex,MOI.EqualTo{Float64}}(
        gb.element_to_graph_map[nvref].value
    )
    cref = gb.graph_to_element_map[ci]
    return cref
end

function JuMP.fix(nvref::NodeVariableRef, value::Number; force::Bool=false)
    if !JuMP.isfinite(value)
        error("Unable to fix variable to $(value)")
    end
    node = nvref.node
    _set_dirty(node)
    _moi_fix_nv(nvref, value, force, Float64)
    return
end

function _moi_fix_nv(
    nvref::NodeVariableRef,
    value::Number,
    force::Bool,
    ::Type{T}
) where {T}
    node = JuMP.owner_model(nvref)
    new_set = MOI.EqualTo(convert(T, value))
    if _moi_nv_is_fixed(nvref)
        cref = _nv_fix_ref(nvref)
        MOI.set(node, MOI.ConstraintSet(), cref, new_set)
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
                MOI.delete(node, _nv_upper_bound_ref(nvref))
            end
            if _moi_nv_has_lower_bound(nvref)
                MOI.delete(node, _nv_lower_bound_ref(nvref))
            end
        end
        con = JuMP.ScalarConstraint(nvref, new_set)
        _moi_add_node_constraint(node, con)
    end
    return
end

function JuMP.is_fixed(nvref::NodeVariableRef)
    return _moi_nv_is_fixed(nvref)
end

function _moi_nv_is_fixed(nvref::NodeVariableRef)
    gb = graph_backend(nvref.node)
    ci = MOI.ConstraintIndex{MOI.VariableIndex,MOI.EqualTo{Float64}}(
        gb.element_to_graph_map[nvref].value
    )
    return MOI.is_valid(gb, ci)
end

function JuMP.fix_value(nvref::NodeVariableRef)
    set = MOI.get(JuMP.owner_model(nvref), MOI.ConstraintSet(), JuMP.FixRef(nvref))
    return set.value
end

function JuMP.unfix(nvref::NodeVariableRef)
    JuMP.delete(JuMP.owner_model(nvref), JuMP.FixRef(nvref))
    return
end

### node variable integer

function JuMP.IntegerRef(nvref::NodeVariableRef)
    if !JuMP.is_integer(nvref)
        error("Variable $nvref is not integer.")
    end
    return _nv_integer_ref(nvref)
end

function _nv_integer_ref(nvref::NodeVariableRef)
    gb = graph_backend(nvref.node)
    ci = MOI.ConstraintIndex{MOI.VariableIndex,MOI.Integer}(
        gb.element_to_graph_map[nvref].value
    )
    cref = gb.graph_to_element_map[ci]
    return cref
end

function JuMP.is_integer(nvref::NodeVariableRef)
    return _moi_nv_is_integer(nvref)
end

function _moi_nv_is_integer(nvref::NodeVariableRef)
    gb = graph_backend(nvref.node)
    ci = MOI.ConstraintIndex{MOI.VariableIndex,MOI.Integer}(
        gb.element_to_graph_map[nvref].value
    )
    return MOI.is_valid(gb, ci)
end

function JuMP.set_integer(nvref::NodeVariableRef)
    node = JuMP.owner_model(nvref)
    _set_dirty(node)
    _moi_set_integer_nv(nvref)
    return
end

function _moi_set_integer_nv(nvref::NodeVariableRef)
    node = JuMP.owner_model(nvref)
    if _moi_nv_is_integer(nvref)
        return
    elseif _moi_nv_is_binary(nvref)
        error(
            "Cannot set the variable_ref $(nvref) to integer as it " *
            "is already binary.",
        )
    end
    con = JuMP.ScalarConstraint(nvref, MOI.Integer())
    _moi_add_node_constraint(node, con)
    return
end

function JuMP.unset_integer(nvref::NodeVariableRef)
    JuMP.delete(JuMP.owner_model(nvref), JuMP.IntegerRef(nvref))
    return
end

### node variable binary

function JuMP.BinaryRef(nvref::NodeVariableRef)
    if !JuMP.is_binary(nvref)
        error("Variable $nvref is not binary.")
    end
    return _nv_binary_ref(nvref)
end

function _nv_binary_ref(nvref::NodeVariableRef)
    gb = graph_backend(nvref.node)
    ci = MOI.ConstraintIndex{MOI.VariableIndex,MOI.ZeroOne}(
        gb.element_to_graph_map[nvref].value
    )
    cref = gb.graph_to_element_map[ci]
    return cref
end

function JuMP.is_binary(nvref::NodeVariableRef)
    return _moi_nv_is_binary(nvref)
end

function _moi_nv_is_binary(nvref::NodeVariableRef)
    gb = graph_backend(nvref.node)
    ci = MOI.ConstraintIndex{MOI.VariableIndex,MOI.ZeroOne}(
        gb.element_to_graph_map[nvref].value
    )
    return MOI.is_valid(gb, ci)
end

function JuMP.set_binary(nvref::NodeVariableRef)
    node = JuMP.owner_model(nvref)
    _set_dirty(node)
    _moi_set_binary_nv(nvref)
    return
end

function _moi_set_binary_nv(nvref::NodeVariableRef)
    node = JuMP.owner_model(nvref)
    if _moi_nv_is_binary(nvref)
        return
    elseif _moi_nv_is_integer(nvref)
        error(
            "Cannot set the variable_ref $(nvref) to binary as it " *
            "is already integer.",
        )
    end
    con = JuMP.ScalarConstraint(nvref, MOI.ZeroOne())
    _moi_add_node_constraint(node, con)
    return
end

function JuMP.unset_binary(nvref::NodeVariableRef)
    JuMP.delete(JuMP.owner_model(nvref), JuMP.BinaryRef(nvref))
    return
end

### Node Constraints

"""
    JuMP.add_constraint(node::OptiNode, con::JuMP.AbstractConstraint, base_name::String="")

Add a constraint `con` to optinode `node`. This function supports use of the @constraint JuMP macro.
"""
function JuMP.add_constraint(
    node::OptiNode, con::JuMP.AbstractConstraint, name::String=""
)
    con = JuMP.model_convert(node, con)
    cref = _moi_add_node_constraint(node, con)
    return cref
end

# TODO: update to use backend lookup
function JuMP.num_constraints(
    node::OptiNode,
    ::Type{F}, 
    ::Type{S}
)::Int64 where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    g2n = graph_backend(node).graph_to_element_map
    cons = MOI.get(JuMP.backend(node), MOI.ListOfConstraintIndices{F,S}())
    refs = [g2n[con] for con in cons]
    return length(filter((cref) -> cref.model == node, refs))
end

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

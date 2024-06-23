# TODO: parameterize on precision
# TODO: move low-level methods to graph backend
# TODO: start values

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

function MOI.get(
    node::OptiNode, 
    attr::MOI.AbstractVariableAttribute,
    nvref::NodeVariableRef
)
    return MOI.get(graph_backend(node), attr, nvref)
end

function MOI.set(
    node::OptiNode,
    attr::MOI.AbstractVariableAttribute,
    nvref::NodeVariableRef,  
    args...
)
    for graph in containing_optigraphs(node)
        MOI.set(graph_backend(graph), attr, nvref, args...)
    end
    return
end

function MOI.delete(node::OptiNode, vref::NodeVariableRef)
    for graph in containing_optigraphs(node)
        MOI.delete(graph_backend(graph), vref)
    end
    return
end

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
    return vref
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
        _add_variable_to_backend(graph_backend(graph), vref)
    end

    # constrain node variable (hits all graph backends)
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
        # MOI.set hits all backends
        MOI.set(
            nvref.node,
            MOI.VariablePrimalStart(),
            nvref,
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

### variable values

function JuMP.value(nvref::NodeVariableRef; result::Int=1)
    return MOI.get(graph_backend(nvref.node), MOI.VariablePrimal(result), nvref)
end

function JuMP.value(var_value::Function, vref::NodeVariableRef)
    return var_value(vref)
end

### variable start values

function JuMP.start_value(nvref::NodeVariableRef)
    return MOI.get(graph_backend(nvref.node), MOI.VariablePrimalStart(), nvref)
end

_convert_if_something(::Type{T}, x) where {T} = convert(T, x)
_convert_if_something(::Type, ::Nothing) = nothing
function JuMP.set_start_value(nvref::NodeVariableRef, value::Union{Nothing,Real})
    # NOTE: sets the start value in all backends
    MOI.set(
        nvref.node, # graph_backend(nvref.node),
        MOI.VariablePrimalStart(),
        nvref,
        _convert_if_something(Float64, value),
    )
end

### node variable bounds

function JuMP.has_lower_bound(nvref::NodeVariableRef)
    return _moi_nv_has_lower_bound(nvref)
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
    backend = graph_backend(nvref.node)
    ci = MOI.ConstraintIndex{MOI.VariableIndex,MOI.GreaterThan{Float64}}(
        graph_index(backend, nvref).value
    )
    return MOI.is_valid(backend, ci)
end

function _nv_lower_bound_ref(nvref::NodeVariableRef)
    backend = graph_backend(nvref.node)
    ci = MOI.ConstraintIndex{MOI.VariableIndex,MOI.GreaterThan{Float64}}(
        graph_index(backend, nvref).value
    )
    cref = JuMP.constraint_ref_with_index(backend, ci)
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
    return _moi_nv_has_upper_bound(nvref)
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

function JuMP.upper_bound(nvref::NodeVariableRef)
    set = MOI.get(JuMP.owner_model(nvref), MOI.ConstraintSet(), JuMP.UpperBoundRef(nvref))
    return set.upper
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
    backend = graph_backend(nvref.node)
    ci = MOI.ConstraintIndex{MOI.VariableIndex,MOI.LessThan{Float64}}(
        graph_index(backend, nvref).value
    )
    return MOI.is_valid(backend, ci)
end

function _nv_upper_bound_ref(nvref::NodeVariableRef)
    backend = graph_backend(nvref.node)
    ci = MOI.ConstraintIndex{MOI.VariableIndex,MOI.LessThan{Float64}}(
        graph_index(backend, nvref).value
    )
    cref = JuMP.constraint_ref_with_index(backend, ci)
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
    backend = graph_backend(nvref.node)
    ci = MOI.ConstraintIndex{MOI.VariableIndex,MOI.EqualTo{Float64}}(
        graph_index(backend, nvref).value
    )
    cref = JuMP.constraint_ref_with_index(backend, ci)
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
    backend = graph_backend(nvref.node)
    ci = MOI.ConstraintIndex{MOI.VariableIndex,MOI.EqualTo{Float64}}(
        graph_index(backend, nvref).value
    )
    return MOI.is_valid(backend, ci)
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
    backend = graph_backend(nvref.node)
    ci = MOI.ConstraintIndex{MOI.VariableIndex,MOI.Integer}(
        graph_index(backend, nvref).value
    )
    cref = JuMP.constraint_ref_with_index(backend, ci)
    return cref
end

function JuMP.is_integer(nvref::NodeVariableRef)
    return _moi_nv_is_integer(nvref)
end

function _moi_nv_is_integer(nvref::NodeVariableRef)
    backend = graph_backend(nvref.node)
    ci = MOI.ConstraintIndex{MOI.VariableIndex,MOI.Integer}(
        graph_index(backend, nvref).value
    )
    return MOI.is_valid(backend, ci)
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
    backend = graph_backend(nvref.node)
    ci = MOI.ConstraintIndex{MOI.VariableIndex,MOI.ZeroOne}(
        graph_index(backend, nvref).value
    )
    cref = JuMP.constraint_ref_with_index(backend, ci)
    return cref
end

function JuMP.is_binary(nvref::NodeVariableRef)
    return _moi_nv_is_binary(nvref)
end

function _moi_nv_is_binary(nvref::NodeVariableRef)
    backend = graph_backend(nvref.node)
    ci = MOI.ConstraintIndex{MOI.VariableIndex,MOI.ZeroOne}(
        graph_index(backend, nvref).value
    )
    return MOI.is_valid(backend, ci)
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
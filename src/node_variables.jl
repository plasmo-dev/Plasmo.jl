# TODO: parameterize on precision

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

function NodeVariableRef(cref::JuMP.ConstraintRef)
    constraint = JuMP.constraint_object(cref)
    nvref = JuMP.jump_function(constraint)
    @assert nvref isa NodeVariableRef
    return nvref
end

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

function get_node(nvref::NodeVariableRef)
    return JuMP.owner_model(nvref)
end

"""
    MOI.get(node::OptiNode, attr::MOI.AbstractVariableAttribute, nvref::NodeVariableRef)

Get the MOI variable attribute given by `attr` for the variable `nvref`. This returns
the attribute from model backend corresponding to the `node`.
"""
function MOI.get(
    node::OptiNode, attr::MOI.AbstractVariableAttribute, nvref::NodeVariableRef
)
    return MOI.get(graph_backend(node), attr, nvref)
end

function MOI.set(
    node::OptiNode, attr::MOI.AbstractVariableAttribute, nvref::NodeVariableRef, args...
)
    for graph in containing_optigraphs(node)
        MOI.set(graph_backend(graph), attr, nvref, args...)
    end
    return nothing
end

function MOI.delete(node::OptiNode, vref::NodeVariableRef)
    for graph in containing_optigraphs(node)
        MOI.delete(graph_backend(graph), vref)
    end
    return nothing
end

"""
    JuMP.add_variable(node::OptiNode, v::JuMP.AbstractVariable, name::String="")

Add variable `v` to optinode `node`. This function supports use of the `@variable` JuMP macro.
Optionally add a `base_name` to the variable for printing.
"""
function JuMP.add_variable(node::OptiNode, v::JuMP.AbstractVariable, name::String="")
    vref = _moi_add_node_variable(node, v)
    if !isempty(name) && MOI.supports(
        JuMP.backend(graph_backend(node)), MOI.VariableName(), MOI.VariableIndex
    )
        JuMP.set_name(vref, "$(JuMP.name(node))[:$(name)]")
    end
    return vref
end

function _moi_add_node_variable(node::OptiNode, v::JuMP.AbstractVariable)
    # get a new variable index and create a reference
    variable_index = next_variable_index(node)
    nvref = NodeVariableRef(node, variable_index)

    # add variable to all containing optigraphs
    for graph in containing_optigraphs(node)
        MOI.add_variable(graph_backend(graph), nvref)
    end

    # constrain node variable (hits all graph backends)
    _moi_constrain_node_variable(nvref, v.info, Float64)
    return nvref
end

function _moi_constrain_node_variable(nvref::NodeVariableRef, info, ::Type{T}) where {T}
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
        MOI.set(nvref.node, MOI.VariablePrimalStart(), nvref, convert(T, info.start))
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
    return nothing
end

function JuMP.is_valid(node::OptiNode, nvref::NodeVariableRef)
    return node === JuMP.owner_model(nvref) && MOI.is_valid(graph_backend(node), nvref)
end

function JuMP.is_valid(node::OptiNode, cref::ConstraintRef)
    return node === JuMP.owner_model(cref) && MOI.is_valid(graph_backend(node), cref)
end

function JuMP.owner_model(nvref::NodeVariableRef)
    return nvref.node
end

function JuMP.name(nvref::NodeVariableRef)
    return MOI.get(graph_backend(nvref.node), MOI.VariableName(), nvref)
end

function JuMP.set_name(nvref::NodeVariableRef, s::String)
    MOI.set(JuMP.owner_model(nvref), MOI.VariableName(), nvref, s)
    return nothing
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
    return MOI.set(
        nvref.node, MOI.VariablePrimalStart(), nvref, _convert_if_something(Float64, value)
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
    return nothing
end

function JuMP.lower_bound(nvref::NodeVariableRef)
    set = MOI.get(JuMP.owner_model(nvref), MOI.ConstraintSet(), JuMP.LowerBoundRef(nvref))
    return set.lower
end

function JuMP.delete_lower_bound(nvref::NodeVariableRef)
    JuMP.delete(JuMP.owner_model(nvref), JuMP.LowerBoundRef(nvref))
    return nothing
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

function _moi_nv_set_lower_bound(nvref::NodeVariableRef, lower::Number)
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
    return nothing
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
    return nothing
end

function JuMP.upper_bound(nvref::NodeVariableRef)
    set = MOI.get(JuMP.owner_model(nvref), MOI.ConstraintSet(), JuMP.UpperBoundRef(nvref))
    return set.upper
end

function JuMP.delete_upper_bound(nvref::NodeVariableRef)
    JuMP.delete(JuMP.owner_model(nvref), JuMP.UpperBoundRef(nvref))
    return nothing
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

function _moi_nv_set_upper_bound(nvref::NodeVariableRef, upper::Number)
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
    return nothing
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
    return nothing
end

function _moi_fix_nv(
    nvref::NodeVariableRef, value::Number, force::Bool, ::Type{T}
) where {T}
    node = JuMP.owner_model(nvref)
    new_set = MOI.EqualTo(convert(T, value))
    if _moi_nv_is_fixed(nvref)
        cref = _nv_fix_ref(nvref)
        MOI.set(node, MOI.ConstraintSet(), cref, new_set)
    else
        # add a new fixing constraint
        if _moi_nv_has_upper_bound(nvref) || _moi_nv_has_lower_bound(nvref)
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
    return nothing
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
    return nothing
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
    return nothing
end

function _moi_set_integer_nv(nvref::NodeVariableRef)
    node = JuMP.owner_model(nvref)
    if _moi_nv_is_integer(nvref)
        return nothing
    elseif _moi_nv_is_binary(nvref)
        error(
            "Cannot set the variable_ref $(nvref) to integer as it " * "is already binary."
        )
    end
    con = JuMP.ScalarConstraint(nvref, MOI.Integer())
    _moi_add_node_constraint(node, con)
    return nothing
end

function JuMP.unset_integer(nvref::NodeVariableRef)
    JuMP.delete(JuMP.owner_model(nvref), JuMP.IntegerRef(nvref))
    return nothing
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
    return nothing
end

function _moi_set_binary_nv(nvref::NodeVariableRef)
    node = JuMP.owner_model(nvref)
    if _moi_nv_is_binary(nvref)
        return nothing
    elseif _moi_nv_is_integer(nvref)
        error(
            "Cannot set the variable_ref $(nvref) to binary as it " * "is already integer."
        )
    end
    con = JuMP.ScalarConstraint(nvref, MOI.ZeroOne())
    _moi_add_node_constraint(node, con)
    return nothing
end

function JuMP.unset_binary(nvref::NodeVariableRef)
    JuMP.delete(JuMP.owner_model(nvref), JuMP.BinaryRef(nvref))
    return nothing
end

# Extended from https://github.com/jump-dev/JuMP.jl/blob/301d46e81cb66c74c6e22cd89fb89ced740f157b/src/variables.jl#L2721
function JuMP.set_normalized_coefficient(
    con_ref::S, variable::NodeVariableRef, value::Number
) where {S<:Union{NodeConstraintRef,EdgeConstraintRef}}
    graph = owner_model(con_ref).source_graph.x
    _backend = backend(graph)

    MOI.modify(
        _backend.moi_backend,
        graph_index(con_ref),
        MOI.ScalarCoefficientChange(
            graph_index(_backend, variable), convert(Float64, value)
        ),
    )
    graph.is_model_dirty = true
    return nothing
end

function JuMP.set_normalized_coefficient(
    constraints::AbstractVector{<:S},
    variables::AbstractVector{<:NodeVariableRef},
    coeffs::AbstractVector{<:Number},
) where {
    S<:Union{NodeConstraintRef,EdgeConstraintRef,Union{NodeConstraintRef,EdgeConstraintRef}}
}
    c, n, m = length(constraints), length(variables), length(coeffs)
    if !(c == n == m)
        msg = "The number of constraints ($c), variables ($n) and coefficients ($m) must match"
        throw(DimensionMismatch(msg))
    end
    graph = [owner_model(con).source_graph.x for con in constraints]
    _backends = unique(backend.(graph))
    if length(_backends) != 1
        error(
            "Constraints belong to different graph backends; make sure constraints all come from the same graph",
        )
    end
    _backend = _backends[1]
    graph = graph[1]

    MOI.modify(
        _backend.moi_backend,
        graph_index.(Ref(_backend), constraints),
        MOI.ScalarCoefficientChange.(
            graph_index.(Ref(_backend), variables), convert.(Float64, coeffs)
        ),
    )
    graph.is_model_dirty = true
    return nothing
end

function JuMP.set_normalized_coefficient(
    constraint::S, variable::NodeVariableRef, new_coefficients::Vector{Tuple{Int64,T}}
) where {T,S<:Union{NodeConstraintRef,EdgeConstraintRef}}
    graph = owner_model(con_ref).source_graph.x
    _backend = backend(graph)

    MOI.modify(
        _backend.moi_backend,
        graph_index(_backend, constraint),
        MOI.MultirowChange(graph_index(_backend, variable), new_coefficients),
    )
    graph.is_model_dirty = true
    return nothing
end

function JuMP.set_normalized_coefficients(
    constraint::S, variable::NodeVariableRef, new_coefficients::Vector{Tuple{Int64,T}}
) where {T,S<:Union{NodeConstraintRef,EdgeConstraintRef}}
    return JuMP.set_normalized_coefficient(constraint, variable, new_coefficients)
end

function JuMP.set_normalized_coefficient(
    constraint::S, variable_1::NodeVariableRef, variable_2::NodeVariableRef, value::Number
) where {S<:Union{NodeConstraintRef,EdgeConstraintRef}}
    new_value = convert(Float64, value)
    if variable_1 == variable_2
        new_value *= Float64(2)
    end
    graph = owner_model(constraint).source_graph.x
    _backend = backend(graph)
    MOI.modify(
        _backend.moi_backend,
        graph_index(_backend, constraint),
        MOI.ScalarQuadraticCoefficientChange(
            graph_index(_backend, variable_1), graph_index(_backend, variable_2), new_value
        ),
    )
    graph.is_model_dirty = true
    return nothing
end

function JuMP.set_normalized_coefficient(
    constraints::AbstractVector{S},
    variables_1::AbstractVector{<:NodeVariableRef},
    variables_2::AbstractVector{<:NodeVariableRef},
    coeffs::AbstractVector{<:Number},
) where {S<:Union{NodeConstraintRef,EdgeConstraintRef}}
    c, m = length(constraints), length(coeffs)
    n1, n2 = length(variables_1), length(variables_1)
    if !(c == n1 == n2 == m)
        msg = "The number of constraints ($c), variables ($n1, $n2) and coefficients ($m) must match"
        throw(DimensionMismatch(msg))
    end
    new_coeffs = convert.(Float64, coeffs)
    for (i, x, y) in zip(eachindex(new_coeffs), variables_1, variables_2)
        if x == y
            new_coeffs[i] *= T(2)
        end
    end
    graph = [owner_model(con).source_graph.x for con in constraints]
    _backends = unique(backend.(graph))
    if length(_backends) != 1
        error(
            "Constraints belong to different graph backends; make sure constraints all come from the same graph",
        )
    end
    _backend = _backends[1]
    graph = graph[1]
    MOI.modify(
        _backend.moi_backend,
        graph_index.(Ref(_backend), constraints),
        MOI.ScalarQuadraticCoefficientChange.(
            graph_index.(Ref(_backend), variables_1),
            graph_index.(Ref(_backend), variables_2),
            new_coeffs,
        ),
    )
    graph.is_model_dirty = true
    return nothing
end

### Utilities for querying variables used in constraints

function _extract_variables(func::NodeVariableRef)
    return [func]
end

function _extract_variables(ref::ConstraintRef)
    func = JuMP.jump_function(JuMP.constraint_object(ref))
    return _extract_variables(func)
end

function _extract_variables(func::JuMP.GenericAffExpr)
    return collect(keys(func.terms))
end

function _extract_variables(func::JuMP.GenericQuadExpr)
    quad_vars = vcat([[term[2]; term[3]] for term in JuMP.quad_terms(func)]...)
    aff_vars = _extract_variables(func.aff)
    return union(quad_vars, aff_vars)
end

function _extract_variables(func::JuMP.GenericNonlinearExpr)
    vars = NodeVariableRef[]
    for i in 1:length(func.args)
        func_arg = func.args[i]
        if func_arg isa Number
            continue
        elseif typeof(func_arg) == NodeVariableRef
            push!(vars, func_arg)
        else
            append!(vars, _extract_variables(func_arg))
        end
    end
    return vars
end

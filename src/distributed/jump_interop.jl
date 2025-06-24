# This file mostly extends the functions of `jump_interop.jl` for the ordinary optigraph
# to the RemoteOptiGraph case

#TODO: I think perhaps we could make an abstractnodevariableref type which NodeVariableRef and RemoteVariableRef are subtypes of so that we can just have one set of MOI functions we are extending instead of two
JuMP.variable_ref_type(::Type{T} where {T<:RemoteOptiObject}) = RemoteVariableRef
JuMP.jump_function(::RemoteOptiObject, x::Number) = convert(Float64, x)

function JuMP.jump_function_type(::RemoteOptiObject, ::Type{MOI.VariableIndex})
    return RemoteVariableRef
end

function MOI.ScalarAffineFunction(a::GenericAffExpr{C,<:RemoteVariableRef}) where {C}
    _assert_isfinite(a)
    terms = MOI.ScalarAffineTerm{C}[
        MOI.ScalarAffineTerm(t[1], index(t[2])) for t in linear_terms(a)
    ]
    return MOI.ScalarAffineFunction(terms, a.constant)
end

function JuMP.jump_function_type(
    obj::RemoteOptiObject, ::Type{MOI.ScalarAffineFunction{C}}
) where {C}
    return JuMP.GenericAffExpr{C,RemoteVariableRef}
end

function JuMP.jump_function(obj::RemoteOptiObject, f::MOI.ScalarAffineFunction{C}) where {C}
    return JuMP.GenericAffExpr{C,RemoteVariableRef}(obj, f)
end

function MOI.ScalarQuadraticFunction(q::GenericQuadExpr{C,RemoteVariableRef}) where {C}
    _assert_isfinite(q)
    qterms = MOI.ScalarQuadraticTerm{C}[_moi_quadratic_term(t) for t in quad_terms(q)]
    moi_aff = MOI.ScalarAffineFunction(q.aff)
    return MOI.ScalarQuadraticFunction(qterms, moi_aff.terms, moi_aff.constant)
end

function JuMP.jump_function_type(
    obj::RemoteOptiObject, ::Type{MOI.ScalarQuadraticFunction{C}}
) where {C}
    return JuMP.GenericQuadExpr{C,RemoteVariableRef}
end

function JuMP.jump_function(obj::RemoteOptiObject, f::MOI.ScalarQuadraticFunction{C}) where {C}
    return JuMP.GenericQuadExpr{C,RemoteVariableRef}(obj, f)
end

function JuMP.jump_function_type(obj::RemoteOptiObject, ::Type{MOI.ScalarNonlinearFunction})
    V = JuMP.variable_ref_type(typeof(obj))
    return JuMP.GenericNonlinearExpr{V}
end

function JuMP.jump_function(node::RemoteNodeRef, f::MOI.ScalarNonlinearFunction)
    V = JuMP.variable_ref_type(typeof(node))
    ret = JuMP.GenericNonlinearExpr{V}(f.head, Any[])
    stack = Tuple{JuMP.GenericNonlinearExpr,Any}[]
    for arg in reverse(f.args)
        push!(stack, (ret, arg))
    end
    while !isempty(stack)
        parent, arg = pop!(stack)
        if arg isa MOI.ScalarNonlinearFunction
            new_ret = JuMP.GenericNonlinearExpr{V}(arg.head, Any[])
            push!(parent.args, new_ret)
            for child in reverse(arg.args)
                push!(stack, (new_ret, child))
            end
        else
            push!(parent.args, JuMP.jump_function(node, arg))
        end
    end
    return ret
end

function JuMP.jump_function(edge::RemoteEdgeRef, f::MOI.ScalarNonlinearFunction)
    V = JuMP.variable_ref_type(typeof(edge))
    ret = JuMP.GenericNonlinearExpr{V}(f.head, Any[])
    stack = Tuple{JuMP.GenericNonlinearExpr,Any}[]
    for arg in reverse(f.args)
        push!(stack, (ret, arg))
    end
    while !isempty(stack)
        parent, arg = pop!(stack)
        if arg isa MOI.ScalarNonlinearFunction
            new_ret = JuMP.GenericNonlinearExpr{V}(arg.head, Any[])
            push!(parent.args, new_ret)
            for child in reverse(arg.args)
                push!(stack, (new_ret, child))
            end
        else
            push!(parent.args, JuMP.jump_function(edge, arg))
        end
    end
    return ret
end

function JuMP.jump_function(graph::RemoteOptiGraph, f::MOI.ScalarNonlinearFunction)
    V = JuMP.variable_ref_type(typeof(graph))
    ret = JuMP.GenericNonlinearExpr{V}(f.head, Any[])
    stack = Tuple{JuMP.GenericNonlinearExpr,Any}[]
    for arg in reverse(f.args)
        push!(stack, (ret, arg))
    end
    while !isempty(stack)
        parent, arg = pop!(stack)
        if arg isa MOI.ScalarNonlinearFunction
            new_ret = JuMP.GenericNonlinearExpr{V}(arg.head, Any[])
            push!(parent.args, new_ret)
            for child in reverse(arg.args)
                push!(stack, (new_ret, child))
            end
        else
            push!(parent.args, JuMP.jump_function(graph, arg))
        end
    end
    return ret
end

function JuMP._error_if_cannot_register(rnode::RemoteNodeRef, name::Symbol)
    return nothing
end

# function JuMP._error_if_cannot_register(rnode::RemoteOptiGraph, name::Symbol)
#     return nothing
# end

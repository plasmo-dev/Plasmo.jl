# this file contains the necessary JuMP methods to work with JuMP expressions.

### directly copied functions from JuMP
# copied from: https://github.com/jump-dev/JuMP.jl/blob/0df25a9185ceede762af533bc965c9374c97450c/src/constraints.jl
function _moi_add_constraint(
    model::MOI.ModelLike,
    f::F,
    s::S,
) where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    if !MOI.supports_constraint(model, F, S)
        error(
            "Constraints of type $(F)-in-$(S) are not supported by the " *
            "solver.\n\nIf you expected the solver to support your problem, " *
            "you may have an error in your formulation. Otherwise, consider " *
            "using a different solver.\n\nThe list of available solvers, " *
            "along with the problem types they support, is available at " *
            "https://jump.dev/JuMP.jl/stable/installation/#Supported-solvers.",
        )
    end
    return MOI.add_constraint(model, f, s)
end

### Variables

JuMP.variable_ref_type(::Type{T} where T <: OptiObject) = NodeVariableRef

JuMP.jump_function(::OptiObject, x::Number) = convert(Float64, x)

function JuMP.jump_function_type(
    ::OptiObject,
    ::Type{MOI.VariableIndex},
)
    return NodeVariableRef
end

function JuMP.jump_function(obj::OptiObject, vidx::MOI.VariableIndex)
    gb = graph_backend(obj)
    node_var = gb.graph_to_element_map[vidx]
    node = node_var.node
    return NodeVariableRef(node, node_var.index)
end

### Affine Expressions
# adapted from: https://github.com/jump-dev/JuMP.jl/blob/master/src/aff_expr.jl

function _assert_isfinite(a::JuMP.GenericAffExpr)
    for (coef, var) in linear_terms(a)
        if !isfinite(coef)
            error("Invalid coefficient $coef on variable $var.")
        end
    end
    if isnan(a.constant)
        error(
            "Expression contains an invalid NaN constant. This could be " *
            "produced by `Inf - Inf`.",
        )
    end
    return
end

function MOI.ScalarAffineFunction(
    a::GenericAffExpr{C,<:NodeVariableRef},
) where {C}
    _assert_isfinite(a)
    terms = MOI.ScalarAffineTerm{C}[
        MOI.ScalarAffineTerm(t[1], index(t[2])) for t in linear_terms(a)
    ]
    return MOI.ScalarAffineFunction(terms, a.constant)
end

function JuMP.jump_function_type(
    obj::OptiObject,
    ::Type{MOI.ScalarAffineFunction{C}},
) where {C}
    return JuMP.GenericAffExpr{C,NodeVariableRef}
end

function JuMP.jump_function(
    obj::OptiObject,
    f::MOI.ScalarAffineFunction{C},
) where {C}
    return JuMP.GenericAffExpr{C,NodeVariableRef}(obj, f)
end

function JuMP.GenericAffExpr{C,NodeVariableRef}(
    node::OptiNode,
    f::MOI.ScalarAffineFunction,
) where {C}
    aff = GenericAffExpr{C,NodeVariableRef}(f.constant)
    for t in f.terms
        node_var_index = graph_backend(node).graph_to_element_map[t.variable].index
        JuMP.add_to_expression!(
            aff,
            t.coefficient,
            NodeVariableRef(node, node_var_index),
        )
    end
    return aff
end

function JuMP.GenericAffExpr{C,NodeVariableRef}(
    edge::OptiEdge,
    f::MOI.ScalarAffineFunction,
) where {C}
    aff = GenericAffExpr{C,NodeVariableRef}(f.constant)
    # build JuMP Affine Expression over edge variables
    for t in f.terms
        node_var = graph_backend(edge).graph_to_element_map[t.variable]
        node = node_var.node
        node_index = node_var.index
        JuMP.add_to_expression!(
            aff,
            t.coefficient,
            NodeVariableRef(node, node_index),
        )
    end
    return aff
end

function JuMP.GenericAffExpr{C,NodeVariableRef}(
    graph::OptiGraph,
    f::MOI.ScalarAffineFunction,
) where {C}
    aff = GenericAffExpr{C,NodeVariableRef}(f.constant)
    # build JuMP Affine Expression over func variables
    for t in f.terms
        gb = graph_backend(graph)
        node_var = gb.graph_to_element_map[t.variable]
        node = node_var.node
        node_index = node_var.index
        JuMP.add_to_expression!(
            aff,
            t.coefficient,
            NodeVariableRef(node, node_index),
        )
    end
    return aff
end

### Quadratic Expressions
# adapted from: https://github.com/jump-dev/JuMP.jl/blob/master/src/quad_expr.jl

function _moi_quadratic_term(t::Tuple)
    return MOI.ScalarQuadraticTerm(
        t[2] == t[3] ? 2t[1] : t[1],
        index(t[2]),
        index(t[3]),
    )
end

function _assert_isfinite(q::GenericQuadExpr)
    _assert_isfinite(q.aff)
    for (coef, var1, var2) in quad_terms(q)
        isfinite(coef) ||
            error("Invalid coefficient $coef on quadratic term $var1*$var2.")
    end
end

function MOI.ScalarQuadraticFunction(
    q::GenericQuadExpr{C,NodeVariableRef},
) where {C}
    _assert_isfinite(q)
    qterms = MOI.ScalarQuadraticTerm{C}[
        _moi_quadratic_term(t) for t in quad_terms(q)
    ]
    moi_aff = MOI.ScalarAffineFunction(q.aff)
    return MOI.ScalarQuadraticFunction(qterms, moi_aff.terms, moi_aff.constant)
end

function JuMP.jump_function_type(
    obj::OptiObject,
    ::Type{MOI.ScalarQuadraticFunction{C}},
) where {C}
    return JuMP.GenericQuadExpr{C,NodeVariableRef}
end

function JuMP.jump_function(
    obj::OptiObject,
    f::MOI.ScalarQuadraticFunction{C},
) where {C}
    return JuMP.GenericQuadExpr{C,NodeVariableRef}(obj, f)
end

function JuMP.GenericQuadExpr{C,NodeVariableRef}(
    node::OptiNode,
    f::MOI.ScalarQuadraticFunction,
) where {C}
    quad = JuMP.GenericQuadExpr{C,NodeVariableRef}(
        JuMP.GenericAffExpr{C,NodeVariableRef}(
            node,
            MOI.ScalarAffineFunction(f.affine_terms, f.constant),
        ),
    )
    for t in f.quadratic_terms
        v1 = graph_backend(node).graph_to_element_map[t.variable_1].index
        v2 = graph_backend(node).graph_to_element_map[t.variable_2].index
        coef = t.coefficient
        if v1 == v2
            coef /= 2
        end
        add_to_expression!(
            quad,
            coef,
            NodeVariableRef(node, v1),
            NodeVariableRef(node, v2),
        )
    end
    return quad
end

function JuMP.GenericQuadExpr{C,NodeVariableRef}(
    edge::OptiEdge,
    f::MOI.ScalarQuadraticFunction,
) where {C}
    # affine terms
    quad = JuMP.GenericQuadExpr{C,NodeVariableRef}(
        JuMP.GenericAffExpr{C,NodeVariableRef}(
            edge,
            MOI.ScalarAffineFunction(f.affine_terms, f.constant),
        ),
    )
    # quadratic terms
    for t in f.quadratic_terms
        # node variable indices
        v1 = t.variable_1
        v2 = t.variable_2
        coef = t.coefficient
        if v1 == v2
            coef /= 2
        end

        # variable index 1
        node_var_1 = graph_backend(edge).graph_to_element_map[v1]
        node1 = node_var_1.node
        var_index_1 = node_var_1.index

        # variable index 2
        node_var_2 = graph_backend(edge).graph_to_element_map[v2]
        node2 = node_var_2.node
        var_index_2 = node_var_2.index

        # add to quadratic expression
        add_to_expression!(
            quad,
            coef,
            NodeVariableRef(node1, var_index_1),
            NodeVariableRef(node2, var_index_2),
        )
    end
    return quad
end

function JuMP.GenericQuadExpr{C,NodeVariableRef}(
    graph::OptiGraph,
    f::MOI.ScalarQuadraticFunction,
) where {C}
    # affine terms
    quad = JuMP.GenericQuadExpr{C,NodeVariableRef}(
        JuMP.GenericAffExpr{C,NodeVariableRef}(
            graph,
            MOI.ScalarAffineFunction(f.affine_terms, f.constant),
        ),
    )
    gb = graph_backend(graph)
    # quadratic terms
    for t in f.quadratic_terms
        # node variable indices
        v1 = t.variable_1
        v2 = t.variable_2
        coef = t.coefficient
        if v1 == v2
            coef /= 2
        end

        # variable index 1
        node_var_1 = gb.graph_to_element_map[v1]
        node1 = node_var_1.node
        var_index_1 = node_var_1.index

        # variable index 2
        node_var_2 = gb.graph_to_element_map[v2]
        node2 = node_var_2.node
        var_index_2 = node_var_2.index

        # add to quadratic expression
        add_to_expression!(
            quad,
            coef,
            NodeVariableRef(node1, var_index_1),
            NodeVariableRef(node2, var_index_2),
        )
    end
    return quad
end

### Nonlinear Expressions
# adapted from: https://github.com/jump-dev/JuMP.jl/blob/master/src/nlp_expr.jl

function JuMP.jump_function_type(
    obj::OptiObject,
    ::Type{MOI.ScalarNonlinearFunction},
)
    V = JuMP.variable_ref_type(typeof(obj))
    return JuMP.GenericNonlinearExpr{V}
end

function JuMP.jump_function(node::OptiNode, f::MOI.ScalarNonlinearFunction)
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

function JuMP.jump_function(edge::OptiEdge, f::MOI.ScalarNonlinearFunction)
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

function JuMP.jump_function(graph::OptiGraph, f::MOI.ScalarNonlinearFunction)
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
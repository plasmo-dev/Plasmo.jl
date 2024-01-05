### directly copied functions from JuMP
# TODO: attribute file
function _moi_constrain_node_variable(
    gb::GraphMOIBackend,
    index,
    info,
    ::Type{T},
) where {T}
    if info.has_lb
        _moi_add_constraint(
            gb.moi_backend,
            index,
            MOI.GreaterThan{T}(info.lower_bound),
        )
    end
    if info.has_ub
        _moi_add_constraint(
            gb.moi_backend,
            index,
            MOI.LessThan{T}(info.upper_bound),
        )
    end
    if info.has_fix
        _moi_add_constraint(
            gb.moi_backend,
            index,
            MOI.EqualTo{T}(info.fixed_value),
        )
    end
    if info.binary
        _moi_add_constraint(gb.moi_backend, index, MOI.ZeroOne())
    end
    if info.integer
        _moi_add_constraint(gb.moi_backend, index, MOI.Integer())
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


### functions adapted from: https://github.com/jump-dev/JuMP.jl/blob/0df25a9185ceede762af533bc965c9374c97450c/src/aff_expr.jl

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


function JuMP.GenericAffExpr{C,NodeVariableRef}(
    node::OptiNode,
    f::MOI.ScalarAffineFunction,
) where {C}
    aff = GenericAffExpr{C,NodeVariableRef}(f.constant)
    for t in f.terms
        JuMP.add_to_expression!(
            aff,
            t.coefficient,
            NodeVariableRef(node, t.variable),
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
        # node_var = edge.source_graph.backend.graph_to_node_map[t.variable]
        node_var = graph_backend(edge).graph_to_node_map[t.variable]
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
        node_var = gb.graph_to_node_map[t.variable]
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

### TODO: quadratic interop attribution

function _assert_isfinite(q::GenericQuadExpr)
    _assert_isfinite(q.aff)
    for (coef, var1, var2) in quad_terms(q)
        isfinite(coef) ||
            error("Invalid coefficient $coef on quadratic term $var1*$var2.")
    end
end

function _moi_quadratic_term(t::Tuple)
    return MOI.ScalarQuadraticTerm(
        t[2] == t[3] ? 2t[1] : t[1],
        index(t[2]),
        index(t[3]),
    )
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

function GenericQuadExpr{C,NodeVariableRef}(
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
        v1 = t.variable_1
        v2 = t.variable_2
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

function GenericQuadExpr{C,NodeVariableRef}(
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
        node_var_1 = graph_backend(edge).graph_to_node_map[v1]
        node1 = node_var_1.node
        var_index_1 = node_var_1.index

        # variable index 2
        node_var_2 = graph_backend(edge).graph_to_node_map[v2]
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

function GenericQuadExpr{C,NodeVariableRef}(
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
        node_var_1 = graph_backend(edge).graph_to_node_map[v1]
        node1 = node_var_1.node
        var_index_1 = node_var_1.index

        # variable index 2
        node_var_2 = graph_backend(edge).graph_to_node_map[v2]
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

function GenericQuadExpr{C,NodeVariableRef}(
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
        node_var_1 = gb.graph_to_node_map[v1]
        node1 = node_var_1.node
        var_index_1 = node_var_1.index

        # variable index 2
        node_var_2 = gb.graph_to_node_map[v2]
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

function JuMP.GenericAffExpr{C,NodeVariableRef}(
    graph::OptiGraph,
    f::MOI.ScalarAffineFunction,
) where {C}
    aff = GenericAffExpr{C,NodeVariableRef}(f.constant)
    for t in f.terms
        gb = graph_backend(graph)
        node_var = gb.graph_to_node_map[t.variable]
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
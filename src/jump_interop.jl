# copied from: https://github.com/jump-dev/JuMP.jl/blob/f496535f560ea1a6bbf5df19031997bdcc1e4022/src/aff_expr.jl#L651
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

# Adapted from: https://github.com/jump-dev/JuMP.jl/blob/0df25a9185ceede762af533bc965c9374c97450c/src/aff_expr.jl#L633-L641
function MOI.ScalarAffineFunction(
    a::GenericAffExpr{C,<:NodeVariableRef},
) where {C}
    _assert_isfinite(a)
    terms = MOI.ScalarAffineTerm{C}[
        MOI.ScalarAffineTerm(t[1], index(t[2])) for t in linear_terms(a)
    ]
    return MOI.ScalarAffineFunction(terms, a.constant)
end

# Adapted from: https://github.com/jump-dev/JuMP.jl/blob/0df25a9185ceede762af533bc965c9374c97450c/src/aff_expr.jl#L706-L719
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
function JuMP._init_NLP(graph::OptiGraph)
    graph.nlp_data = JuMP._NLPData()
end


#Functions copied from JuMP.jl.  These would be necessary to do nonlinear LinkConstraints
function JuMP._parse_NL_expr_runtime(graph::OptiGraph, x::Real, tape, parent, values)
    push!(values, x)
    push!(tape, JuMP.NodeData(JuMP.VALUE, length(values), parent))
    nothing
end

function JuMP._parse_NL_expr_runtime(graph::OptiGraph, x::JuMP.VariableRef, tape, parent, values)
    push!(tape, JuMP.NodeData(JuMP.MOIVARIABLE, x.index.value, parent))
    nothing
end

function JuMP._parse_NL_expr_runtime(graph::OptiGraph, x::NonlinearExpression, tape, parent, values)
    push!(tape, JuMP.NodeData(JuMP.SUBEXPRESSION, x.index, parent))
    nothing
end

function JuMP._parse_NL_expr_runtime(graph::OptiGraph, x::NonlinearParameter, tape, parent, values)
    push!(tape, JuMP.NodeData(JuMP.PARAMETER, x.index, parent))
    nothing
end

function JuMP._parse_NL_expr_runtime(graph::OptiGraph, x::AbstractArray, tape, parent, values)
    error("Unexpected array $x in nonlinear expression. Nonlinear expressions may contain only scalar expressions.")
end

function JuMP._parse_NL_expr_runtime(graph::OptiGraph, x::GenericQuadExpr, tape, parent, values)
    error("Unexpected quadratic expression $x in nonlinear expression. " *
          "Quadratic expressions (e.g., created using @expression) and " *
          "nonlinear expressions cannot be mixed.")
end

function JuMP._parse_NL_expr_runtime(graph::OptiGraph, x::GenericAffExpr, tape, parent, values)
    error("Unexpected affine expression $x in nonlinear expression. " *
          "Affine expressions (e.g., created using @expression) and " *
          "nonlinear expressions cannot be mixed.")
end

function JuMP._parse_NL_expr_runtime(graph::OptiGraph, x, tape, parent, values)
    error("Unexpected object $x (of type $(typeof(x)) in nonlinear expression.")
end

JuMP.name(cref::ConstraintRef{OptiGraph,NonlinearConstraintIndex,ScalarShape}) = "test"
# JuMP.constraint_object(ref::ConstraintRef{OptiGraph,NonlinearConstraintIndex,ScalarShape}) =
# JuMP.object_dictionary(m::OptiGraph) = m.objdict


#PRINTING
function JuMP._tape_to_expr(m::OptiGraph, k, nd::Vector{JuMP.NodeData}, adj, const_values,
                      parameter_values, subexpressions::Vector{Any},
                      user_operators::JuMP._Derivatives.UserOperatorRegistry,
                      generic_variable_names::Bool, splat_subexpressions::Bool,
                      print_mode=REPLMode)
        return JuMP._tape_to_expr(Model(),k, nd, adj, const_values,
                              parameter_values, subexpressions,
                              user_operators,
                              generic_variable_names, splat_subexpressions,
                              print_mode)

end

#------------------------------------------------------------------------
## _NonlinearExprData
#------------------------------------------------------------------------
function JuMP.nl_expr_string(model::OptiGraph, mode, c::JuMP._NonlinearExprData)
    return string(JuMP._tape_to_expr(model, 1, c.nd, JuMP.adjmat(c.nd), c.const_values,
                                [], [], model.nlp_data.user_operators, false,
                                false, mode))
end

#------------------------------------------------------------------------
## _NonlinearConstraint
#------------------------------------------------------------------------
#TODO
const NonlinearLinkConstraintRef = ConstraintRef{OptiGraph, NonlinearConstraintIndex}

function Base.show(io::IO, c::NonlinearLinkConstraintRef)
    print(io, JuMP.nl_constraint_string(c.model, REPLMode, c.model.nlp_data.nlconstr[c.index.value]))
end

function Base.show(io::IO, ::MIME"text/latex", c::NonlinearLinkConstraintRef)
    constraint = c.model.nlp_data.nlconstr[c.index.value]
    print(io, JuMP._wrap_in_math_mode(JuMP.nl_constraint_string(c.model, IJuliaMode, constraint)))
end

function JuMP.nl_constraint_string(model::OptiGraph, mode, c::JuMP._NonlinearConstraint)
    s = JuMP._sense(c)
    nl = JuMP.nl_expr_string(model, mode, c.terms)
    if s == :range
        out_str = "$(_string_round(c.lb)) " * _math_symbol(mode, :leq) *
                  " $nl " * _math_symbol(mode, :leq) * " " * _string_round(c.ub)
    else
        if s == :<=
            rel = JuMP._math_symbol(mode, :leq)
        elseif s == :>=
            rel = JuMP._math_symbol(mode, :geq)
        else
            rel = JuMP._math_symbol(mode, :eq)
        end
        out_str = string(nl, " ", rel, " ", JuMP._string_round(JuMP._rhs(c)))
    end
    return out_str
end

#TODO
# function JuMP.NLPEvaluator(graph::OptiGraph)
#     model = Model()
#     model.ext[:graph] = graph
#     model.nlp_data = graph.nlp_data
#     vars = JuMP.all_node_variables(graph)  #oredered by order of node
#     #We shouldn't need other variable information since we only want to be able to get constraint information.  We would never pass this model to a solver.
#     for var in vars
#         @variable(model,var)
#     end
#     #Need to add the constraints in too
#     d = JuMP.NLPEvaluator(model)
#     return d
# end

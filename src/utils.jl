"""
    extract_variables(func)

Return the variables contained within the given expression or reference.
"""
function extract_variables(func)
    return _extract_variables(func)
end

function _extract_variables(func::NodeVariableRef)
    return [func]
end

function _extract_variables(ref::EdgeConstraintRef)
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
    V = typeof(func).parameters[1]
    vars = V[]
    for i in 1:length(func.args)
        func_arg = func.args[i]
        if func_arg isa Number
            continue
        elseif typeof(func_arg) == V
            push!(vars, func_arg)
        else
            append!(vars, _extract_variables(func_arg))
        end
    end
    return vars
end

function _first_variable(func::JuMP.GenericNonlinearExpr)
    V = typeof(func).parameters[1]
    for i in 1:length(func.args)
        func_arg = func.args[i]
        if func_arg isa Number
            continue
        elseif typeof(func_arg) == V
            return func_arg
        else
            return _first_variable(func_arg)
        end
    end
end

"""
    is_separable(func)

Return whether the given function is separable across optinodes.
"""
function is_separable(func::Union{Number,JuMP.AbstractJuMPScalar})
    return _is_separable(func)
end

function _is_separable(::Number)
    return true
end

function _is_separable(::NodeVariableRef)
    return true
end

function _is_separable(::JuMP.GenericAffExpr{<:Number,NodeVariableRef})
    return true
end

function _is_separable(func::JuMP.GenericQuadExpr{<:Number,NodeVariableRef})
    # check each term; make sure they are all on the same subproblem
    for term in Plasmo.quad_terms(func)
        # term = (coefficient, variable_1, variable_2)
        node1 = get_node(term[2])
        node2 = get_node(term[3])

        # if any term is split across nodes, the objective is not separable
        if node1 != node2
            return false
        end
    end
    return true
end

function _is_separable(func::JuMP.GenericNonlinearExpr{NodeVariableRef})
    # check for a constant multiplier
    if func.head == :*
        if !(func.args[1] isa Number)
            return false
        end
    end

    # if not additive, check if term is separable
    if func.head != :+ && func.head != :-
        vars = extract_variables(func)
        nodes = get_node.(vars)
        if length(unique(nodes)) > 1
            return false
        end
    end

    # check each argument
    for arg in func.args
        if !(is_separable(arg))
            return false
        end
    end
    return true
end

"""
    extract_separable_terms(func::JuMP.AbstractJuMPScalar,graph::OptiGraph)

Extract the separable terms contained within `graph`.
NOTE: Nonlinear objectives are not completely tested and may return incorrect results.
"""
function extract_separable_terms(func::JuMP.AbstractJuMPScalar, graph::OptiGraph)
    !is_separable(func) && error("Cannont extract terms. Function is not separable.")
    return _extract_separable_terms(func, graph)
end

function _extract_separable_terms(
    func::Union{Number,Plasmo.NodeVariableRef}, graph::OptiGraph
)
    return func
end

function _extract_separable_terms(
    func::JuMP.GenericAffExpr{<:Number,NodeVariableRef}, graph::OptiGraph
)
    node_terms = OrderedDict{
        OptiNode,Vector{JuMP.GenericAffExpr{<:Number,NodeVariableRef}}
    }()
    nodes = Plasmo.collect_nodes(func)
    nodes = intersect(nodes, all_nodes(graph))
    for node in nodes
        node_terms[node] = Vector{JuMP.GenericAffExpr{<:Number,NodeVariableRef}}()
    end

    for term in Plasmo.linear_terms(func)
        node = get_node(term[2])
        push!(node_terms[node], term[1] * term[2])
    end

    return node_terms
end

function _extract_separable_terms(
    func::JuMP.GenericQuadExpr{<:Number,NodeVariableRef}, graph::OptiGraph
)
    node_terms = OrderedDict{
        OptiNode,Vector{JuMP.GenericQuadExpr{<:Number,NodeVariableRef}}
    }()
    nodes = collect_nodes(func)
    nodes = intersect(nodes, all_nodes(graph))
    for node in nodes
        node_terms[node] = Vector{JuMP.GenericQuadExpr{<:Number,NodeVariableRef}}()
    end

    for term in JuMP.quad_terms(func)
        node = get_node(term[2])
        push!(node_terms[node], term[1] * term[2] * term[3])
    end

    for term in JuMP.linear_terms(func)
        node = get_node(term[2])
        push!(node_terms[node], term[1] * term[2])
    end

    return node_terms
end

# NOTE: method needs improvement. does not cover all separable cases.
function _extract_separable_terms(
    func::JuMP.GenericNonlinearExpr{NodeVariableRef}, graph::OptiGraph
)
    node_terms = OrderedDict{OptiNode,Vector{JuMP.GenericNonlinearExpr{NodeVariableRef}}}()
    nodes = collect_nodes(func)
    nodes = intersect(nodes, all_nodes(graph))
    for node in nodes
        node_terms[node] = Vector{JuMP.GenericNonlinearExpr{NodeVariableRef}}()
    end

    _extract_separable_terms(func, node_terms)

    return node_terms
end

function _extract_separable_terms(
    func::JuMP.GenericNonlinearExpr{NodeVariableRef},
    node_terms::OrderedDict{OptiNode,Vector{JuMP.GenericNonlinearExpr{NodeVariableRef}}},
)
    # check for a constant multiplier
    multiplier = 1.0
    if func.head == :*
        if func.args[1] isa Number
            multiplier = func.args[1]
        end
    end

    # if not additive, get node for this term
    if func.head != :+ && func.head != :-
        var = _first_variable(func)
        node = get_node(var)
        push!(node_terms[node], multiplier * func)
    else
        # check each argument
        for arg in func.args
            if arg isa Number
                continue
            end
            _extract_separable_terms(arg, node_terms)
        end
    end

    return nothing
end

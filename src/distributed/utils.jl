function _extract_variables(func::RemoteVariableRef)
    return [func]
end

function _extract_variables(ref::RemoteEdgeConstraintRef)
    func = JuMP.jump_function(JuMP.constraint_object(ref))
    return _extract_variables(func)
end

"""
    is_separable(func)

Return whether the given function is separable across optinodes.
"""

function _is_separable(::RemoteVariableRef)
    return true
end

function _is_separable(::JuMP.GenericAffExpr{<:Number,RemoteVariableRef})
    return true
end

function _is_separable(func::JuMP.GenericQuadExpr{<:Number,RemoteVariableRef})
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

function _is_separable(func::JuMP.GenericNonlinearExpr{RemoteVariableRef})
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
function extract_separable_terms(func::JuMP.AbstractJuMPScalar, graph::RemoteOptiGraph)
    !is_separable(func) && error("Cannont extract terms. Function is not separable.")
    return _extract_separable_terms(func, graph)
end

function _extract_separable_terms(
    func::Union{Number,Plasmo.RemoteVariableRef}, graph::RemoteOptiGraph
)
    return func
end

function _extract_separable_terms(
    func::JuMP.GenericAffExpr{<:Number,RemoteVariableRef}, graph::RemoteOptiGraph
)
    node_terms = OrderedDict{
        RemoteNodeRef,Vector{JuMP.GenericAffExpr{<:Number,RemoteVariableRef}}
    }()
    nodes = Plasmo.collect_nodes(func)
    nodes = intersect(nodes, all_nodes(graph))
    for node in nodes
        node_terms[node] = Vector{JuMP.GenericAffExpr{<:Number,RemoteVariableRef}}()
    end

    for term in Plasmo.linear_terms(func)
        node = get_node(term[2])
        push!(node_terms[node], term[1] * term[2])
    end

    return node_terms
end

function _extract_separable_terms(
    func::JuMP.GenericQuadExpr{<:Number,RemoteVariableRef}, graph::RemoteOptiGraph
)
    node_terms = OrderedDict{
        RemoteNodeRef,Vector{JuMP.GenericQuadExpr{<:Number,RemoteVariableRef}}
    }()
    nodes = collect_nodes(func)
    nodes = intersect(nodes, all_nodes(graph))
    for node in nodes
        node_terms[node] = Vector{JuMP.GenericQuadExpr{<:Number,RemoteVariableRef}}()
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
    func::JuMP.GenericNonlinearExpr{RemoteVariableRef}, graph::RemoteOptiGraph
)
    node_terms = OrderedDict{RemoteNodeRef,Vector{JuMP.GenericNonlinearExpr{RemoteVariableRef}}}()
    nodes = collect_nodes(func)
    nodes = intersect(nodes, all_nodes(graph))
    for node in nodes
        node_terms[node] = Vector{JuMP.GenericNonlinearExpr{RemoteVariableRef}}()
    end

    _extract_separable_terms(func, node_terms)

    return node_terms
end

function _extract_separable_terms(
    func::JuMP.GenericNonlinearExpr{RemoteVariableRef},
    node_terms::OrderedDict{RemoteNodeRef,Vector{JuMP.GenericNonlinearExpr{RemoteVariableRef}}},
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

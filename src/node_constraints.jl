function MOI.get(
    node::OptiNode, 
    attr::MOI.AbstractConstraintAttribute,
    cref::ConstraintRef
)
    return MOI.get(graph_backend(node), attr, cref)
end

function MOI.set(
    node::OptiNode,
    attr::MOI.AbstractConstraintAttribute,
    cref::ConstraintRef,
    args...
)
    for graph in containing_optigraphs(JuMP.owner_model(cref))
        gb = graph_backend(graph)
        graph_index = gb.element_to_graph_map[cref]
        MOI.set(gb, attr, graph_index, args...)
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
    _check_node_variables(node, jump_func)
    moi_func = JuMP.moi_function(con)
    moi_set = JuMP.moi_set(con)

    # create constraint reference
    constraint_index = next_constraint_index(
        node, 
        typeof(moi_func), 
        typeof(moi_set)
    )::MOI.ConstraintIndex{typeof(moi_func),typeof(moi_set)}
    cref = ConstraintRef(node, constraint_index, JuMP.shape(con))

    # add to each containing optigraph
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

function _check_node_variables(
    node::OptiNode, 
    jump_func::Union{
        NodeVariableRef, 
        JuMP.GenericAffExpr, 
        JuMP.GenericQuadExpr,
        JuMP.GenericNonlinearExpr
    }
)
    return isempty(setdiff(_extract_variables(jump_func), JuMP.all_variables(node)))
end


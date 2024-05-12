function Base.string(node::OptiNode)
    return "$(node.label)"
end
Base.print(io::IO, node::OptiNode) = Base.print(io, Base.string(node))
Base.show(io::IO, node::OptiNode) = Base.print(io, node)

function Base.setindex!(node::OptiNode, value::Any, name::Symbol)
    t = (node, name)
    source_graph(node).node_obj_dict[t] = value
    return
end

function Base.getindex(node::OptiNode, name::Symbol)
    t = (node,name)
    return source_graph(node).node_obj_dict[t]
end

function JuMP.num_variables(node::OptiNode)
    return MOI.get(graph_backend(node), MOI.NumberOfVariables(), node)
    #return length(graph_backend(node).node_variables[node])
end

function JuMP.all_variables(node::OptiNode)
    gb = graph_backend(node)
    graph_indices = gb.node_variables[node]
    return getindex.(Ref(gb.graph_to_element_map), graph_indices)
end

"""
    next_variable_index(node::OptiNode)

Return the next variable index that would be created on this node.
"""
function next_variable_index(node::OptiNode)
    return MOI.VariableIndex(JuMP.num_variables(node) + 1)
end

"""
    graph_backend(node::OptiNode)

Return the `GraphMOIBackend` that holds the associated node model attributes
"""
function graph_backend(node::OptiNode)
    return graph_backend(source_graph(node))
end

"""
    source_graph(node::OptiNode)

Return the optigraph that contains the optinode. This is the optigraph that 
defined said node and stores node object dictionary data.
"""
function source_graph(node::OptiNode)
    return node.source_graph.x
end

function containing_optigraphs(node::OptiNode)
    source = source_graph(node)
    graphs = [source]
    if haskey(source.node_to_graphs, node)
        graphs = [graphs; source.node_to_graphs[node]]
    end
    return graphs
end

function containing_backends(node::OptiNode)
    return graph_backend.(containing_optigraphs(node))
end

"""
    Filter the object dictionary for values that belong to node. Keep in mind that 
this function is slow for optigraphs with many nodes.
"""
function node_object_dictionary(node::OptiNode)
    d = JuMP.object_dictionary(node::OptiNode)
    return filter(p -> p.first[1] == node, d)
    return d
end

function next_constraint_index(
    node::OptiNode, 
    ::Type{F}, 
    ::Type{S}
)::MOI.ConstraintIndex{F,S} where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    index = MOI.get(graph_backend(node), MOI.NumberOfConstraints{F,S}(), node)
    return MOI.ConstraintIndex{F,S}(index + 1)
end

### JuMP Methods

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
    JuMP.add_constraint(node::OptiNode, con::JuMP.AbstractConstraint, name::String="")

Add a constraint `con` to optinode `node`. This function supports use of the @constraint 
JuMP macro.
"""
function JuMP.add_constraint(
    node::OptiNode, con::JuMP.AbstractConstraint, name::String=""
)
    con = JuMP.model_convert(node, con)
    cref = _moi_add_node_constraint(node, con)
    return cref
end

# function JuMP.num_constraints(
#     node::OptiNode,
#     function_type::Type{
#         <:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}},
#     },
#     set_type::Type{<:MOI.AbstractSet},
# )::Int64
#     F = JuMP.moi_function_type(function_type)
#     return MOI.get(graph_backend(node), MOI.NumberOfConstraints{F,set_type}(), node)
# end

function JuMP.object_dictionary(node::OptiNode)
    d = source_graph(node).node_obj_dict
    return d
end

function JuMP.backend(node::OptiNode)
    return JuMP.backend(graph_backend(node))
end

function JuMP.add_nonlinear_operator(
    node::OptiNode,
    dim::Int,
    f::Function,
    args::Vararg{Function,N};
    name::Symbol = Symbol(f),
) where {N}
    nargs = 1 + N
    if !(1 <= nargs <= 3)
        error(
            "Unable to add operator $name: invalid number of functions " *
            "provided. Got $nargs, but expected 1 (if function only), 2 (if " *
            "function and gradient), or 3 (if function, gradient, and " *
            "hesssian provided)",
        )
    end
    name = Symbol(node.label, ".", name)
    MOI.set(graph_backend(node), MOI.UserDefinedFunction(name, dim), tuple(f, args...))
    return JuMP.NonlinearOperator(f, name)
end

function _set_dirty(node::OptiNode)
    for graph in containing_optigraphs(node)
        graph.is_model_dirty = true
    end
    return
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

### MOI Methods

# TODO: store objective functions on nodes and query as node attributes

function MOI.get(node::OptiNode, attr::MOI.AnyAttribute)
    return MOI.get(graph_backend(node), attr)
end

# function MOI.get(node::OptiNode, attr::MOI.UserDefinedFunction)
#     return MOI.get(graph_backend(node), attr)
# end

# TODO: consider caching constraint types in graph backend versus using unique to filter
function MOI.get(node::OptiNode, attr::MOI.ListOfConstraintTypesPresent)
    cons = graph_backend(node).element_constraints[node]
    con_types = unique(typeof.(cons))
    type_tuple = [(type.parameters[1],type.parameters[2]) for type in con_types]  
    return type_tuple
end

function MOI.get(
    node::OptiNode, 
    attr::MOI.ListOfConstraintIndices{F,S}
) where {F <: MOI.AbstractFunction, S <: MOI.AbstractSet}
    con_inds = MOI.ConstraintIndex{F,S}[]
    for con in graph_backend(node).element_constraints[node]
        if (typeof(con).parameters[1] == F && typeof(con).parameters[2] == S)
            push!(con_inds, con)
        end
    end
    return con_inds
end

# function MOI.get(
#     node::OptiNode, 
#     attr::MOI.ListOfConstraintIndices{F,S}
# ) where {F <: MOI.AbstractFunction, S <: MOI.AbstractSet}
#     con_inds = MOI.ConstraintIndex{F,S}[]
#     for con in graph_backend(node).element_constraints[node]
#         if (typeof(con).parameters[1] == F && typeof(con).parameters[2] == S)
#             push!(con_inds, con)
#         end
#     end
#     return con_inds
# end

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
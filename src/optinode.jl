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
    return length(graph_backend(node).node_variables[node])
end

function JuMP.all_variables(node::OptiNode)
    gb = graph_backend(node)
    graph_indices = gb.node_variables[node]
    return getindex.(Ref(gb.graph_to_element_map), graph_indices)
end

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

### JuMP Extension

function JuMP.object_dictionary(node::OptiNode)
    d = source_graph(node).node_obj_dict
    #return filter(p -> p.first[1] == node, d)
    return d
end

"""
    Filter the object dictionary for values that belong to node
"""
function node_object_dictionary(node::OptiNode)
    d = JuMP.object_dictionary(node::OptiNode)
    return filter(p -> p.first[1] == node, d)
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

### MOI Extension

# TODO: store objective functions on nodes and query as node attributes
# function MOI.get(node::OptiNode, attr::MOI.AnyAttribute)
#     return MOI.get(graph_backend(node), attr)
# end

function MOI.get(node::OptiNode, attr::MOI.UserDefinedFunction)
    return MOI.get(graph_backend(node), attr)
end

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
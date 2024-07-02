function Base.string(edge::OptiEdge)
    return "$(edge.label)"
end
Base.print(io::IO, edge::OptiEdge) = Base.print(io, Base.string(edge))
Base.show(io::IO, edge::OptiEdge) = Base.print(io, edge)

function Base.setindex!(edge::OptiEdge, value::Any, name::Symbol)
    t = (edge, name)
    source_graph(edge).edge_obj_dict[t] = value
    return nothing
end

function Base.getindex(edge::OptiEdge, name::Symbol)
    t = (edge, name)
    return edge.source_graph.edge_obj_dict[t]
end

"""
    graph_backend(edge::OptiEdge)

Return the `GraphMOIBackend` that holds the associated edge model attributes
"""
function graph_backend(edge::OptiEdge)
    return graph_backend(source_graph(edge))
end

"""
    source_graph(edge::OptiEdge)

Return the optigraph that contains the optiedge. This is the optigraph that 
defined said edge and stores edge object dictionary data.
"""
function source_graph(edge::OptiEdge)
    return edge.source_graph.x
end

function containing_optigraphs(edge::OptiEdge)
    source = source_graph(edge)
    graphs = [source]
    if haskey(source.edge_to_graphs, edge)
        graphs = [graphs; source.edge_to_graphs[edge]]
    end
    return graphs
end

function all_nodes(edge::OptiEdge)
    return collect(edge.nodes)
end

function JuMP.object_dictionary(edge::OptiEdge)
    d = source_graph(edge).edge_obj_dict
    return filter(p -> p.first[1] == edge, d)
end

function JuMP.backend(edge::OptiEdge)
    return graph_backend(edge)
end

### Edge Variables

function JuMP.all_variables(edge::OptiEdge)
    gb = graph_backend(edge)
    con_refs = getindex.(Ref(gb.graph_to_element_map), gb.element_constraints[edge])
    vars = vcat(_extract_variables.(con_refs)...)
    return unique(vars)
end

### Edge Constraints

function next_constraint_index(
    edge::OptiEdge, ::Type{F}, ::Type{S}
)::MOI.ConstraintIndex{F,S} where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    index = _num_moi_constraints(edge, F, S)
    return MOI.ConstraintIndex{F,S}(index + 1)
end

function _num_moi_constraints(
    edge::OptiEdge, ::Type{F}, ::Type{S}
)::Int64 where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    # cons = MOI.get(edge, MOI.ListOfConstraintIndices{F,S}())
    # return length(cons)
    return MOI.get(edge, MOI.NumberOfConstraints{F,S}())
end

function JuMP.add_constraint(edge::OptiEdge, con::JuMP.AbstractConstraint, name::String="")
    con = JuMP.model_convert(edge, con)
    cref = _moi_add_edge_constraint(edge, con)
    return cref
end

function _moi_add_edge_constraint(edge::OptiEdge, con::JuMP.AbstractConstraint)
    # get moi function and set
    jump_func = JuMP.jump_function(con)
    moi_func = JuMP.moi_function(con)
    moi_set = JuMP.moi_set(con)

    # create constraint index and reference
    constraint_index = next_constraint_index(
        edge, typeof(moi_func), typeof(moi_set)
    )::MOI.ConstraintIndex{typeof(moi_func),typeof(moi_set)}
    cref = ConstraintRef(edge, constraint_index, JuMP.shape(con))

    # update graph backends
    for graph in containing_optigraphs(edge)
        # add backend variables if linking across optigraphs
        _add_backend_variables(graph_backend(graph), jump_func)

        # update the moi function variable indices
        moi_func_graph = _create_graph_moi_func(graph_backend(graph), moi_func, jump_func)

        # add the constraint to the backend
        _add_element_constraint_to_backend(
            graph_backend(graph), cref, moi_func_graph, moi_set
        )
    end
    return cref
end

function JuMP.is_valid(edge::OptiEdge, cref::ConstraintRef)
    return edge === JuMP.owner_model(cref) && MOI.is_valid(graph_backend(edge), cref)
end

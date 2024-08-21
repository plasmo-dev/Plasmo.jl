#  Copyright 2021, Jordan Jalving, Yankai Cao, Victor Zavala, and contributors
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at https://mozilla.org/MPL/2.0/.

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
    source_data = source.element_data
    graphs = [source]
    if haskey(source_data.edge_to_graphs, edge)
        graphs = [graphs; source_data.edge_to_graphs[edge]]
    end
    return graphs
end

function all_nodes(edge::OptiEdge)
    return collect(edge.nodes)
end

function edge_object_dictionary(edge::OptiEdge)
    d = source_graph(edge).element_data.edge_obj_dict
    return filter(p -> p.first[1] == edge, d)
end

function JuMP.object_dictionary(edge::OptiEdge)
    d = source_graph(edge).element_data.edge_obj_dict
    return d
    # return filter(p -> p.first[1] == edge, d)
end

function JuMP.backend(edge::OptiEdge)
    return graph_backend(edge)
end

### Edge Variables

function JuMP.all_variables(edge::OptiEdge)
    con_refs = JuMP.all_constraints(edge)
    vars = vcat(_extract_variables.(con_refs)...)
    return unique(vars)
end

function JuMP.delete(graph::OptiGraph, cref::ConstraintRef)
    if typeof(JuMP.owner_model(cref)) == OptiNode{OptiGraph}
        error(
            "You have passed a node constraint but specified an OptiGraph." *
            "Use `JuMP.delete(::OptiNode, ::ConstraintRef)` instead",
        )
    end
    if graph !== source_graph(JuMP.owner_model(cref))
        error(
            "The constraint reference you are trying to delete does not" *
            "belong to the specified graph",
        )
    end
    _set_dirty(graph)
    MOI.delete(JuMP.owner_model(cref), cref)
    #TODO: Probably need to delete the edge altogether if it is the only constraint on the edge
end

### Edge Constraints

# NOTE: could use one method for node and edge
function next_constraint_index(
    edge::OptiEdge, ::Type{F}, ::Type{S}
)::MOI.ConstraintIndex{F,S} where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    source_data = source_graph(edge).element_data
    if !haskey(source_data.last_constraint_index, edge)
        source_data.last_constraint_index[edge] = 0
    end
    source_data.last_constraint_index[edge] += 1
    return MOI.ConstraintIndex{F,S}(source_data.last_constraint_index[edge])
end

function _num_moi_constraints(
    edge::OptiEdge, ::Type{F}, ::Type{S}
)::Int64 where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
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

    # add to each containing optigraph
    for graph in containing_optigraphs(edge)
        MOI.add_constraint(
            graph_backend(graph), cref, jump_func, moi_set; add_variables=true
        )
    end
    return cref
end

function JuMP.is_valid(edge::OptiEdge, cref::ConstraintRef)
    return edge === JuMP.owner_model(cref) && MOI.is_valid(graph_backend(edge), cref)
end

"""
    JuMP.dual(cref::EdgeConstraintRef; result::Int=1)

Return the dual for an `EdgeConstraintRef`. This returns the dual for the source graph that
corresponds to the constraint reference.
"""
function JuMP.dual(cref::EdgeConstraintRef; result::Int=1)
    return MOI.get(graph_backend(cref.model), MOI.ConstraintDual(result), cref)
end

struct OptiEdge{GT<:AbstractOptiGraph} <: JuMP.AbstractModel
    source_graph::GT
    label::Symbol
    nodes::OrderedSet{OptiNode}
end
function Base.string(edge::OptiEdge)
    return "$(edge.label)"
end
Base.print(io::IO, edge::OptiEdge) = Base.print(io, Base.string(edge))
Base.show(io::IO, edge::OptiEdge) = Base.print(io, edge)

function Base.setindex!(edge::OptiEdge, value::Any, name::Symbol)
    t = (edge, name)
    edge.source_graph.edge_obj_dict[t] = value
    return
end

function Base.getindex(edge::OptiEdge, name::Symbol)
    t = (edge,name)
    return edge.source_graph.edge_obj_dict[t]
end

"""
    graph_backend(edge::OptiEdge)

Return the `GraphMOIBackend` that holds the associated edge model attributes
"""
function graph_backend(edge::OptiEdge)
    return graph_backend(optimizer_graph(edge))
end

"""
    source_graph(edge::OptiEdge)

Return the optigraph that contains the optiedge. This is the optigraph that 
defined said edge and stores edge object dictionary data.
"""
function source_graph(edge::OptiEdge)
    return edge.source_graph
end

"""
    backend_graph(edge::OptiEdge)

Return the `OptiGraph` that contains the edge model attributes. In most cases, this is the 
same as `source_graph(edge)`. For improved performance when modeling with subgraphs, it is 
possible to define all node and edge attributes on the parent-level graph. In this case,
`backend_graph(edge)` would return a parent graph, whereas `source_graph(edge)` would return
the subgraph that contains the node.
"""
function optimizer_graph(edge::OptiEdge)
    return source_graph(edge).optimizer_graph
end

function containing_optigraphs(edge::OptiEdge)
    source = source_graph(edge)
    backend = optimizer_graph(edge)
    graphs = [backend]
    if haskey(source.edge_to_graphs, edge)
        graphs = [graphs; source_graph.edge_to_graphs[edge]]
    end
    return graphs
end

### OptiEdge Extension

function MOI.get(edge::OptiEdge, attr::MOI.AbstractConstraintAttribute, ref::ConstraintRef)
    return MOI.get(graph_backend(edge), attr, ref)
end

function JuMP.object_dictionary(edge::OptiEdge)
    return edge.source_graph.edge_obj_dict
end

function JuMP.backend(edge::OptiEdge)
    return JuMP.backend(graph_backend(edge))
end

function JuMP.jump_function(
    edge::OptiEdge,
    f::MOI.ScalarAffineFunction{C},
) where {C}
    return JuMP.GenericAffExpr{C,NodeVariableRef}(edge, f)
end

function JuMP.jump_function(
    edge::OptiEdge,
    f::MOI.ScalarQuadraticFunction{C},
) where {C}
    return JuMP.GenericQuadExpr{C,NodeVariableRef}(edge, f)
end

function JuMP.num_constraints(
    edge::OptiEdge,
    ::Type{F}, 
    ::Type{S}
)::Int64 where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    # TODO: more efficent method to track number of constraints on nodes and edges
    g2e = graph_backend(edge).graph_to_node_map
    cons = MOI.get(JuMP.backend(edge),MOI.ListOfConstraintIndices{F,S}())
    refs = [g2e[con] for con in cons]
    return length(filter((cref) -> cref.model == edge, refs))
end

### Edge Constraints

function JuMP.add_constraint(
    edge::OptiEdge, con::JuMP.AbstractConstraint, name::String=""
)
    con = JuMP.model_convert(edge, con)
    cref = _moi_add_edge_constraint(edge, con)
    # TODO: set constraint name
    return cref
end
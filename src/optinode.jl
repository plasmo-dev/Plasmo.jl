struct NodeIndex
    value::Int
end

struct OptiNode{GT<:AbstractOptiGraph} <: JuMP.AbstractModel
    source_graph::GT
    idx::NodeIndex
    label::Symbol
end

function Base.string(node::OptiNode)
    return "$(node.label)"
end
Base.print(io::IO, node::OptiNode) = Base.print(io, Base.string(node))
Base.show(io::IO, node::OptiNode) = Base.print(io, node)

function Base.setindex!(node::OptiNode, value::Any, name::Symbol)
    t = (node, name)
    node.source_graph.node_obj_dict[t] = value
    return
end

function Base.getindex(node::OptiNode, name::Symbol)
    t = (node,name)
    return node.source_graph.node_obj_dict[t]
end

"""
    graph_backend(node::OptiNode)

Return the `GraphMOIBackend` that holds the associated node model attributes
"""
function graph_backend(node::OptiNode)
    return graph_backend(optimizer_graph(node))
end

"""
    source_graph(node::OptiNode)

Return the optigraph that contains the optinode. This is the optigraph that 
defined said node and stores node object dictionary data.
"""
function source_graph(node::OptiNode)
    return node.source_graph
end

"""
    optimizer_graph(node::OptiNode)

Return the `OptiGraph` that contains the node backend attributes. In most cases, this is the 
same as `source_graph(node)`. For improved performance when modeling with subgraphs, it is 
possible to define all node and edge attributes on a parent graph as opposed to 
the source graph. In this case, `backend_graph(node)` would return said parent graph, 
whereas `source_graph(node)` would return the subgraph.
"""
function optimizer_graph(node::OptiNode)
    return source_graph(node).optimizer_graph
end

function containing_optigraphs(node::OptiNode)
    source = source_graph(node)
    backend_graph = optimizer_graph(node)
    graphs = [backend_graph]
    if haskey(source.node_to_graphs, node)
        graphs = [graphs; source_graph.node_to_graphs[node]]
    end
    return graphs
end

function containing_backends(node::OptiNode)
    return graph_backend.(containing_optigraphs(node))
end

function _set_dirty(node::OptiNode)
    for graph in containing_optigraphs(node)
        graph.is_model_dirty = true
    end
    return
end

### OptiNode MOI Extension

function MOI.get(node::OptiNode, attr::MOI.AnyAttribute)
    return MOI.get(graph_backend(node), attr)
end

function MOI.get(node::OptiNode, attr::MOI.AbstractConstraintAttribute, ref::ConstraintRef)
    return MOI.get(graph_backend(node), attr, ref)
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

function MOI.delete(node::OptiNode, vref::NodeVariableRef)
    for graph in containing_optigraphs(node)
        MOI.delete(graph_backend(graph), vref)
    end
    return
end

function MOI.delete(node::OptiNode, cref::ConstraintRef)
    for graph in containing_optigraphs(node)
        MOI.delete(graph_backend(graph), cref)
    end
    return
end

### JuMP Extension

function JuMP.object_dictionary(node::OptiNode)
    return node.source_graph.node_obj_dict
end

function JuMP.backend(node::OptiNode)
    return JuMP.backend(graph_backend(node))
end

### Node Variables

struct NodeVariableRef <: JuMP.AbstractVariableRef
    node::OptiNode
    index::MOI.VariableIndex
end

function Base.string(vref::NodeVariableRef)
    return JuMP.name(vref)
end
Base.print(io::IO, vref::NodeVariableRef) = Base.print(io, Base.string(vref))
Base.show(io::IO, vref::NodeVariableRef) = Base.print(io, vref)
Base.broadcastable(vref::NodeVariableRef) = Ref(vref)

function graph_index(vref::NodeVariableRef)
    return graph_backend(vref.node).element_to_graph_map[vref]
end

"""
    JuMP.add_variable(node::OptiNode, v::JuMP.AbstractVariable, name::String="")

Add variable `v` to optinode `node`. This function supports use of the `@variable` JuMP macro.
Optionally add a `base_name` to the variable for printing.
"""
function JuMP.add_variable(node::OptiNode, v::JuMP.AbstractVariable, name::String="")
    vref = _moi_add_node_variable(node, v)
    if !isempty(name) && MOI.supports(JuMP.backend(node), MOI.VariableName(), MOI.VariableIndex)
        JuMP.set_name(vref, "$(node.label).$(name)")
    end
    return  vref
end

function JuMP.num_variables(node::OptiNode)
    return length(graph_backend(node).node_variables[node])
end

function JuMP.all_variables(node::OptiNode)
    gb = graph_backend(node)
    graph_indices = gb.node_variables[node]
    return getindex.(Ref(gb.graph_to_element_map), graph_indices)
end

function JuMP.delete(node::OptiNode, nvref::NodeVariableRef)
    if node !== JuMP.owner_model(nvref)
        error(
            "The variable reference you are trying to delete does not " *
            "belong to the model.",
        )
    end
    _set_dirty(node)
    for graph in containing_optigraphs(node)
        MOI.delete(graph_backend(node), nvref)
    end
    return
end

function JuMP.is_valid(node::OptiNode, nvref::NodeVariableRef)
    return node === JuMP.owner_model(nvref) &&
           MOI.is_valid(graph_backend(node), nvref)
end

function JuMP.fix(nvref::NodeVariableRef, value::Number; force::Bool=false)
    if !JuMP.isfinite(value)
        error("Unable to fix variable to $(value)")
    end
    node = nvref.node
    _set_dirty(node)
    _moi_fix_node_variable(nvref, value, force, Float64)
    return
end

function JuMP.is_fixed(nvref::NodeVariableRef)
    return _moi_is_nv_fixed(graph_backend(nvref), nvref)
end

function JuMP.has_upper_bound(nvref::NodeVariableRef)
    return _moi_has_upper_bound(graph_backend(nvref), nvref)
end

function JuMP.index(vref::NodeVariableRef)
    return vref.index
end

function JuMP.value(nvref::NodeVariableRef; result::Int = 1)
    return MOI.get(graph_backend(nvref.node), MOI.VariablePrimal(result), nvref)
end

function JuMP.value(var_value::Function, vref::NodeVariableRef)
    return var_value(vref)
end

function JuMP.owner_model(nvref::NodeVariableRef)
    return nvref.node
end

function JuMP.name(vref::NodeVariableRef)
    gb = graph_backend(vref.node)
    return MOI.get(JuMP.backend(vref.node), MOI.VariableName(), gb.element_to_graph_map[vref])
end

function JuMP.set_name(vref::NodeVariableRef, s::String)
    gb = graph_backend(vref.node)
    MOI.set(gb.moi_backend, MOI.VariableName(), gb.element_to_graph_map[vref], s)
    return
end

### Node Constraints

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

function JuMP.delete(node::OptiNode, cref::ConstraintRef)
    if node !== JuMP.owner_model(cref)
        error(
            "The constraint reference you are trying to delete does not " *
            "belong to the model.",
        )
    end
    _set_dirty(node)
    MOI.delete(node, cref)
    # for graph in containing_optigraphs(node)
    #     MOI.delete(graph_backend(node), cref)
    # end
    return
end
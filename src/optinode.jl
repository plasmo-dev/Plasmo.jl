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

Return the `OptiGraph` that contains the node model attributes. In most cases, this is the 
same as `source_graph(node)`. For improved performance when modeling with subgraphs, it is 
possible to define all node and edge attributes on the parent-level graph. In this case,
`backend_graph(node)` would return a parent graph, whereas `source_graph(node)` would return
the subgraph that contains the node.
"""
function optimizer_graph(node::OptiNode)
    return source_graph(node).optimizer_graph
end

function containing_optigraphs(node::OptiNode)
    source = source_graph(node)
    backend = optimizer_graph(node)
    graphs = [backend]
    if haskey(source.node_to_graphs, node)
        graphs = [graphs; source_graph.node_to_graphs[node]]
    end
    return graphs
end

### OptiNode Extension

function MOI.get(node::OptiNode, attr::MOI.AnyAttribute)
    return MOI.get(graph_backend(node), attr)
end

function MOI.get(node::OptiNode, attr::MOI.AbstractConstraintAttribute, ref::ConstraintRef)
    return MOI.get(graph_backend(node), attr, ref)
end

function JuMP.object_dictionary(node::OptiNode)
    return node.source_graph.node_obj_dict
end

function JuMP.backend(node::OptiNode)
    return JuMP.backend(graph_backend(node))
end

# TODO: determine if caching node references is possible without dict-of-dicts
function JuMP.all_variables(node::OptiNode)
    return collect(
        filter(var -> var.node == node, keys(graph_backend(node).node_to_graph_map.var_map))
    )
end

function JuMP.num_variables(node::OptiNode)
    n2g = graph_backend(node).node_to_graph_map
    return length(filter((vref) -> vref.node == node, keys(n2g.var_map)))
end

function JuMP.num_constraints(
    node::OptiNode,
    ::Type{F}, 
    ::Type{S}
)::Int64 where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    g2n = graph_backend(node).graph_to_node_map
    cons = MOI.get(JuMP.backend(node), MOI.ListOfConstraintIndices{F,S}())
    println(cons)
    refs = [g2n[con] for con in cons]
    return length(filter((cref) -> cref.model == node, refs))
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
    return graph_backend(vref.node).node_to_graph_map[vref]
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
    return MOI.get(JuMP.backend(vref.node), MOI.VariableName(), gb.node_to_graph_map[vref])
end

function JuMP.set_name(vref::NodeVariableRef, s::String)
    gb = graph_backend(vref.node)
    MOI.set(gb.moi_backend, MOI.VariableName(), gb.node_to_graph_map[vref], s)
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
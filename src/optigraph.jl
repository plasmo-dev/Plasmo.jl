abstract type AbstractOptiGraph <: JuMP.AbstractModel end

### OptiNode

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

function graph_backend(node::OptiNode)
    return graph_backend(node.source_graph)
end

function containing_optigraphs(node::OptiNode)
    source_graph = node.source_graph
    graphs = [source_graph]
    if haskey(source_graph.node_to_graphs, node)
        graphs = [graphs; source_graph.node_to_graphs[node]]
    end
    return graphs
end

### OptiNode Extension

function MOI.get(node::OptiNode, attr::MOI.AbstractConstraintAttribute, ref::ConstraintRef)
    return MOI.get(graph_backend(node), attr, ref)
end

function JuMP.object_dictionary(node::OptiNode)
    return node.source_graph.node_obj_dict
end

function JuMP.backend(node::OptiNode)
    return JuMP.backend(graph_backend(node))
end

function JuMP.jump_function(
    node::OptiNode,
    f::MOI.ScalarAffineFunction{C},
) where {C}
    return JuMP.GenericAffExpr{C,NodeVariableRef}(node, f)
end

function JuMP.num_constraints(
    node::OptiNode,
    ::Type{F}, 
    ::Type{S}
)::Int64 where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    return MOI.get(JuMP.backend(node), MOI.NumberOfConstraints{F,S}())
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

### OptiEdge

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

function graph_backend(edge::OptiEdge)
    return graph_backend(edge.source_graph)
end

function containing_optigraphs(edge::OptiEdge)
    source_graph = edge.source_graph
    graphs = [source_graph]
    if haskey(source_graph.edge_to_graphs, edge)
        graphs = [graphs; source_graph.node_to_graphs[edge]]
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

function JuMP.num_constraints(
    edge::OptiEdge,
    ::Type{F}, 
    ::Type{S}
)::Int64 where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    return MOI.get(JuMP.backend(edge), MOI.NumberOfConstraints{F,S}())
end


# const NodeOrEdge = Union{OptiNode,OptiEdge}

# struct LinkConstraintRef
#     edge::OptiEdge
#     index::MOI.ConstraintIndex
# end
# Base.broadcastable(c::LinkConstraintRef) = Ref(c)



### OptiGraph

mutable struct OptiGraph <: AbstractOptiGraph
    # topology
    optinodes::Vector{OptiNode}                  #Local optinodes
    optiedges::Vector{OptiEdge}                  #Local optiedges
    subgraphs::Vector{OptiGraph}

    # track node membership in other graphs; nodes use this to query different backends
    node_to_graphs::OrderedDict{OptiNode,Vector{OptiGraph}}
    edge_to_graphs::OrderedDict{OptiEdge,Vector{OptiGraph}}

    backend::MOI.ModelLike

    node_obj_dict::OrderedDict{Tuple{OptiNode,Symbol},Any} # object dictionary for nodes
    edge_obj_dict::OrderedDict{Tuple{OptiEdge,Symbol},Any} # object dictionary for edges
    obj_dict::Dict{Symbol,Any}
    ext::Dict{Symbol,Any}      # extension information

    label::Symbol

    #Constructor
    function OptiGraph(;label::Symbol=Symbol(:g,gensym()))
        optigraph = new()
        optigraph.optinodes = Vector{OptiNode}()
        optigraph.optiedges = Vector{OptiEdge}()
        optigraph.subgraphs = Vector{OptiGraph}()

        optigraph.node_to_graphs = OrderedDict{OptiNode,Vector{OptiGraph}}()
        optigraph.node_obj_dict = OrderedDict{Tuple{OptiNode,Symbol},Any}()
        optigraph.edge_to_graphs = OrderedDict{OptiEdge,Vector{OptiGraph}}()
        optigraph.edge_obj_dict = OrderedDict{Tuple{OptiEdge,Symbol},Any}()

        optigraph.backend = GraphMOIBackend(optigraph)
        optigraph.obj_dict = Dict{Symbol,Any}()
        optigraph.ext = Dict{Symbol,Any}()
        optigraph.label = label
        return optigraph
    end
end

function graph_backend(graph::OptiGraph)
    return graph.backend
end

function Base.string(graph::OptiGraph)
    return "OptiGraph"
end
Base.print(io::IO, graph::OptiGraph) = Base.print(io, Base.string(graph))
Base.show(io::IO, graph::OptiGraph) = Base.print(io, graph)

# TODO: PR for JuMP on name_to_register. This lets us overrride how objects get registered in OptiGraphs
# function JuMP.name_to_register(node::OptiNode, name::Symbol)
#     return (node,name)
# end

### Add Node

function add_node(
    graph::OptiGraph; 
    label=Symbol(graph.label,Symbol(".n"),length(graph.optinodes)+1)
)
    node_index = NodeIndex(length(graph.optinodes)+1)
    optinode = OptiNode{OptiGraph}(graph, node_index, label)
    push!(graph.optinodes, optinode)
    return optinode
end

### Node Variables

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

function JuMP.index(graph::OptiGraph, vref::NodeVariableRef)
    gb = graph_backend(graph)
    return gb.node_to_graph_map[vref]
end

function JuMP.name(vref::NodeVariableRef)
    gb = vref.node.source_graph.backend
    return MOI.get(JuMP.backend(vref.node), MOI.VariableName(), gb.node_to_graph_map[vref])
end

function JuMP.set_name(vref::NodeVariableRef, s::String)
    gb = graph_backend(vref.node)
    MOI.set(gb.moi_backend, MOI.VariableName(), gb.node_to_graph_map[vref], s)
    return
end

function JuMP.num_variables(node::OptiNode)
    n2g = node.source_graph.backend.node_to_graph_map
    return length(filter((vref) -> vref.node == node, keys(n2g.var_map)))
end

### Constraints

### Node Constraints

# NOTE: Using an alias on ConstraintRef{M,C,S} causes issues with dispatching JuMP functions. I'm not sure it is really necessary vs just using ConstraintRef for dispatch.
# const NodeConstraintRef = JuMP.ConstraintRef{OptiNode, MOI.ConstraintIndex{F,S} where {F,S}, Shape where Shape <: JuMP.AbstractShape}
# const NodeConstraintRef = JuMP.ConstraintRef{OptiNode, MOI.ConstraintIndex}



"""
    JuMP.add_constraint(node::OptiNode, con::JuMP.AbstractConstraint, base_name::String="")

Add a constraint `con` to optinode `node`. This function supports use of the @constraint JuMP macro.
"""
function JuMP.add_constraint(
    node::OptiNode, con::JuMP.AbstractConstraint, name::String=""
)
    # TODO: determine whether `model_convert` is necessary?
    con = JuMP.model_convert(node, con)
    cref = _moi_add_node_constraint(node, con)
    return cref
end


"""
    JuMP.add_nonlinear_constraint(node::OptiNode, expr::Expr)

Add a non-linear constraint to an optinode using a Julia expression.
"""
function JuMP.add_nonlinear_constraint(node::OptiNode, expr::Expr)
    cref = JuMP.add_nonlinear_constraint(jump_model(node), expr)
    node_cref = ConstraintRef(node, cref.index, JuMP.ScalarShape())
    return node_cref
end

function JuMP.add_nonlinear_parameter(node::OptiNode, p::Real)
    return JuMP.add_nonlinear_parameter(jump_model(node), p)
end

function JuMP.add_nonlinear_expression(node::OptiNode, expr::Any)
    return JuMP.add_nonlinear_expression(jump_model(node), expr)
end

### Add Edges

function add_edge(
    graph::OptiGraph,
    nodes::OptiNode...;
    label=Symbol(graph.label,Symbol(".e"),length(graph.optiedges)+1)
)
    edge = OptiEdge{OptiGraph}(graph, label, OrderedSet(collect(nodes)))
    push!(graph.optiedges, edge)
    return edge
end

function JuMP.add_constraint(
    edge::OptiEdge, con::JuMP.AbstractConstraint, name::String=""
)
    con = JuMP.model_convert(edge, con) # converts coefficient and constant types
    cref = _moi_add_edge_constraint(edge, con)
    # TODO: set constraint name
    return cref
end

### Objective Function



### JuMP interoperability

# copied from: https://github.com/jump-dev/JuMP.jl/blob/f496535f560ea1a6bbf5df19031997bdcc1e4022/src/aff_expr.jl#L651
function _assert_isfinite(a::GenericAffExpr)
    for (coef, var) in linear_terms(a)
        if !isfinite(coef)
            error("Invalid coefficient $coef on variable $var.")
        end
    end
    if isnan(a.constant)
        error(
            "Expression contains an invalid NaN constant. This could be " *
            "produced by `Inf - Inf`.",
        )
    end
    return
end

# Adapted from: https://github.com/jump-dev/JuMP.jl/blob/0df25a9185ceede762af533bc965c9374c97450c/src/aff_expr.jl#L633-L641
function MOI.ScalarAffineFunction(
    a::GenericAffExpr{C,<:NodeVariableRef},
) where {C}
    _assert_isfinite(a)
    terms = MOI.ScalarAffineTerm{C}[
        MOI.ScalarAffineTerm(t[1], index(t[2])) for t in linear_terms(a)
    ]
    return MOI.ScalarAffineFunction(terms, a.constant)
end

# Adapted from: https://github.com/jump-dev/JuMP.jl/blob/0df25a9185ceede762af533bc965c9374c97450c/src/aff_expr.jl#L706-L719
function JuMP.GenericAffExpr{C,NodeVariableRef}(
    node::OptiNode,
    f::MOI.ScalarAffineFunction,
) where {C}
    aff = GenericAffExpr{C,NodeVariableRef}(f.constant)
    for t in f.terms
        JuMP.add_to_expression!(
            aff,
            t.coefficient,
            NodeVariableRef(node, t.variable),
        )
    end
    return aff
end

function JuMP.GenericAffExpr{C,NodeVariableRef}(
    edge::OptiEdge,
    f::MOI.ScalarAffineFunction,
) where {C}
    aff = GenericAffExpr{C,NodeVariableRef}(f.constant)
    # build JuMP Affine Expression over edge variables
    for t in f.terms
        node_var = edge.source_graph.backend.graph_to_node_map[t.variable]
        node = node_var.node
        node_index = node_var.index
        JuMP.add_to_expression!(
            aff,
            t.coefficient,
            NodeVariableRef(node, node_index),
        )
    end
    return aff
end
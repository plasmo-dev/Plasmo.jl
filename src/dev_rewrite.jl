using JuMP
using MathOptInterface
const MOI = MathOptInterface

abstract type AbstractOptiGraph <: JuMP.AbstractModel

mutable struct OptiGraph{T<:AbstractOptiGraph} <: AbstractOptiGraph #<: JuMP.AbstractModel
    #Topology
    optinodes::Vector{OptiNode}                  #Local optinodes
    optiedges::Vector{OptiEdge}                  #Local optiedges
    subgraphs::Vector{T}
    # node_data::OrderedDict{OptiNode,}

    # IDEA: An optigraph optimizer can be a MOI model.  
    # For standard optimization solvers, we can either:
    # 1) aggregate a MOI backend on the fly using optinodes
    # 2) build up the MOI backend with nodes
    model::GraphBackend

    ext::Dict{Symbol,Any} # extension information
    id::Symbol

    #Constructor
    function OptiGraph()
        optigraph = new(
            Vector{OptiNode}(),
            Vector{OptiEdge}(),
        )
        graph_backend = GraphBackend(optigraph)
        optigraph.moi_backend = graph_backend
        return optigraph
    end
end

struct NodeVariableRef <: JuMP.AbsatractVariableRef
    node::OptiNode
    idx::MOI.VariableIndex
end

Base.broadcastable(v::NodeVariableRef) = Ref(v)

mutable struct OptiNode <: JuMP.AbstractModel
    source_graph::OptiGraph 
    id::Symbol
end

function backend(node::OptiNode)
    return node.source_graph.backend
end

"""
    JuMP.add_variable(node::OptiNode, v::JuMP.AbstractVariable, name::String="")

Add variable `v` to optinode `node`. This function supports use of the `@variable` JuMP macro.
Optionally add a `base_name` to the variable for printing.
"""
function JuMP.add_variable(node::OptiNode, v::JuMP.AbstractVariable, name::String="")
    variable_index = next_variable_index!(node)
    vref = NodeVariableRef(node, variable_index)
    _moi_add_node_variable(node, vref, v)
    if !isempty(name) && MOI.supports(backend(node), MOI.VariableName(), MOI.VariableIndex)
       JuMP.set_name(vref, "$(node.label)[$name]")
    end
    return vref
end

function _moi_add_node_variable(
    vref::NodeVariableRef{T}
    v::JuMP.AbstractVariable
    name::String,
) where {T}
    node = vref.node
    MOI.add_variable(node.source_graph, vref)
    _moi_constrain_variable(node.source_graph, index(node.source_graph, vref), v.info, T)
    for graph in contained_optigraphs(node)
        MOI.add_variable(graph, vref)
         _moi_constrain_variable(graph, index(graph, vref), v.info, T)
    end
    return nothing
end

# TODO: test this out
function JuMP.set_name(v::NodeVariableRef, s::String)
    MOI.set(v.node, MOI.VariableName(), v, s)
    return
end

"""
    JuMP.add_constraint(node::OptiNode, con::JuMP.AbstractConstraint, base_name::String="")

Add a constraint `con` to optinode `node`. This function supports use of the @constraint JuMP macro.
"""
function JuMP.add_constraint(
    node::OptiNode, con::JuMP.AbstractConstraint, base_name::String=""
)
    cref = JuMP.add_constraint(jump_model(node), con, base_name)
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


# an edge has a mapping to source graph
mutable struct OptiEdge <: JuMP.AbstractModel
    source_graph::OptiGraph 
    id::Symbol
end



# IDEAs
# nodes are associated with variables and constraints through GraphBackend

# adding a subgraph can optionally directly update the parent graph

# it is always possible to optimize a subgraph by building a new model

# can't use JuMP.Model for an OptiGraph because it doesn't support linking constraints; we can just create our own optigraph MOI interface
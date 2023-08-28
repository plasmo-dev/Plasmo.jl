abstract type AbstractOptiGraph <: JuMP.AbstractModel end

### OptiNode

struct OptiNode{GT<:AbstractOptiGraph} <: JuMP.AbstractModel
    source_graph::GT
    id::Symbol
    label::String
    obj_dict::Dict{Symbol,Any}
end

function Base.string(node::OptiNode)
    return "$(node.label)"
end
Base.print(io::IO, node::OptiNode) = Base.print(io, Base.string(node))
Base.show(io::IO, node::OptiNode) = Base.print(io, node)
function JuMP.object_dictionary(node::OptiNode)
    return node.obj_dict
end

struct NodeVariableRef <: JuMP.AbstractVariableRef
    node::OptiNode
    index::MOI.VariableIndex
end
Base.broadcastable(v::NodeVariableRef) = Ref(v)
function Base.string(vref::NodeVariableRef)
    return "$(vref.node.label)"*"[$(vref.index.value)]"
end
Base.print(io::IO, vref::NodeVariableRef) = Base.print(io, Base.string(vref))
Base.show(io::IO, vref::NodeVariableRef) = Base.print(io, vref)

struct NodeConstraintRef
    node::OptiNode
    index::MOI.ConstraintIndex
end
Base.broadcastable(c::NodeConstraintRef) = Ref(c)

function backend(node::OptiNode)
    return backend(node.source_graph.backend)
end

function contained_optigraphs(node::OptiNode)
    source_graph = node.source_graph
    # return source_graph.node_data[node].graph_references
    if haskey(source_graph.node_to_graphs, node)
        return source_graph.node_to_graphs[node]
    else
        return OptiGraph[]
    end
end

### OptiEdge

struct OptiEdge{GT<:AbstractOptiGraph} <: JuMP.AbstractModel
    source_graph::GT
    id::Symbol
end

struct LinkConstraintRef
    edge::OptiEdge
    index::MOI.ConstraintIndex
end
Base.broadcastable(c::LinkConstraintRef) = Ref(c)

### OptiGraph

mutable struct OptiGraph <: AbstractOptiGraph #<: JuMP.AbstractModel
    # topology
    optinodes::Vector{OptiNode}                  #Local optinodes
    optiedges::Vector{OptiEdge}                  #Local optiedges
    subgraphs::Vector{OptiGraph}

    # node_data::OrderedDict{OptiNode,NodeData}
    node_to_graphs::OrderedDict{OptiNode,Vector{OptiGraph}}     # track node membership in other graphs; nodes use this to query different backends
    node_var_idx::OrderedDict{OptiNode,Int64}
    # node_obj_dicts::OrderedDict{OptiNode,Dict{Symbol,Any}}

    backend::MOI.ModelLike

    obj_dict::Dict{Symbol,Any}
    ext::Dict{Symbol,Any}      # extension information

    #Constructor
    function OptiGraph()
        optigraph = new()
        optigraph.optinodes = Vector{OptiNode}()
        optigraph.optiedges = Vector{OptiEdge}()
        optigraph.subgraphs = Vector{OptiGraph}()

        optigraph.node_to_graphs = OrderedDict{OptiNode,Vector{OptiGraph}}()
        optigraph.node_var_idx = OrderedDict{OptiNode,Int64}()
        # optigraph.node_obj_dicts = OrderedDict{OptiNode,Dict{Symbol,Any}}()

        #optigraph.node_data = OrderedDict{OptiNode,NodeData}()
        optigraph.backend = GraphBackend(optigraph)
        optigraph.obj_dict = Dict{Symbol,Any}()
        optigraph.ext = Dict{Symbol,Any}()
        return optigraph
    end
end

function Base.string(graph::OptiGraph)
    return "OptiGraph"
end
Base.print(io::IO, graph::OptiGraph) = Base.print(io, Base.string(graph))
Base.show(io::IO, graph::OptiGraph) = Base.print(io, graph)

# function NodeData()
#     return NodeData(0, OptiGraph[], Dict{Symbol,Any}())
# end

function add_node(graph::OptiGraph; label::String="n$(length(graph.optinodes) + 1)")
    optinode = OptiNode(graph, gensym(), label, Dict{Symbol,Any}())
    push!(graph.optinodes, optinode)
    graph.node_var_idx[optinode] = 0
    return optinode
end


function next_variable_index(node::OptiNode)
    current_index = node.source_graph.node_var_idx[node]
    return MOI.VariableIndex(current_index+1)
end

function increment_variable_index!(node::OptiNode)
    node.source_graph.node_var_idx[node] += 1
    return
end

"""
    JuMP.add_variable(node::OptiNode, v::JuMP.AbstractVariable, name::String="")

Add variable `v` to optinode `node`. This function supports use of the `@variable` JuMP macro.
Optionally add a `base_name` to the variable for printing.
"""
function JuMP.add_variable(node::OptiNode, v::JuMP.AbstractVariable, name::String="")
    variable_index = next_variable_index(node)
    vref = NodeVariableRef(node, variable_index)
    _moi_add_node_variable(vref, v)
    increment_variable_index!(node)
    if !isempty(name) && MOI.supports(backend(node), MOI.VariableName(), MOI.VariableIndex)
       JuMP.set_name(vref, "$(node.label)[$name]")
    end
    return vref
end

function _moi_add_node_variable(
    vref::NodeVariableRef,
    v::JuMP.AbstractVariable
)
    node = vref.node
    # add variable to source graph
    graph_index = MOI.add_variable(node.source_graph.backend, vref)
    _moi_constrain_variable(backend(node.source_graph.backend), graph_index, v.info, Float64)
    
    # add variable to all other contained graphs
    for graph in contained_optigraphs(node)
        graph_index = MOI.add_variable(graph)
         _moi_constrain_variable(backend(graph.backend), graph_index, v.info, Float64)
    end
    return nothing
end


function JuMP.index(vref::NodeVariableRef)
    return vref.index
end

function JuMP.index(graph::OptiGraph, vref::NodeVariableRef)
    gb = backend(graph)
    return gb.node_to_graph_map[vref]
end

function JuMP.set_name(v::NodeVariableRef, s::String)
    MOI.set(backend(v.node), MOI.VariableName(), v.index, s)
    return
end



# copied from from: https://github.com/jump-dev/JuMP.jl/blob/master/src/variables.jl
function _moi_add_constraint(
    model::MOI.ModelLike,
    f::F,
    s::S,
) where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    if !MOI.supports_constraint(model, F, S)
        error(
            "Constraints of type $(F)-in-$(S) are not supported by the " *
            "solver.\n\nIf you expected the solver to support your problem, " *
            "you may have an error in your formulation. Otherwise, consider " *
            "using a different solver.\n\nThe list of available solvers, " *
            "along with the problem types they support, is available at " *
            "https://jump.dev/JuMP.jl/stable/installation/#Supported-solvers.",
        )
    end
    return MOI.add_constraint(model, f, s)
end

function _moi_constrain_variable(
    moi_backend::MOI.ModelLike,
    index,
    info,
    ::Type{T},
) where {T}
    if info.has_lb
        _moi_add_constraint(
            moi_backend,
            index,
            MOI.GreaterThan{T}(info.lower_bound),
        )
    end
    if info.has_ub
        _moi_add_constraint(
            moi_backend,
            index,
            MOI.LessThan{T}(info.upper_bound),
        )
    end
    if info.has_fix
        _moi_add_constraint(
            moi_backend,
            index,
            MOI.EqualTo{T}(info.fixed_value),
        )
    end
    if info.binary
        _moi_add_constraint(moi_backend, index, MOI.ZeroOne())
    end
    if info.integer
        _moi_add_constraint(moi_backend, index, MOI.Integer())
    end
    if info.has_start && info.start !== nothing
        MOI.set(
            moi_backend,
            MOI.VariablePrimalStart(),
            index,
            convert(T, info.start),
        )
    end
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




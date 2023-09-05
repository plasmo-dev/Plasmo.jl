abstract type AbstractOptiGraph <: JuMP.AbstractModel end

### OptiNode

struct OptiNode{GT<:AbstractOptiGraph} <: JuMP.AbstractModel
    source_graph::GT
    label::String
end

function Base.string(node::OptiNode)
    return "$(node.label)"
end
Base.print(io::IO, node::OptiNode) = Base.print(io, Base.string(node))
Base.show(io::IO, node::OptiNode) = Base.print(io, node)
function JuMP.object_dictionary(node::OptiNode)
    return node.source_graph.node_obj_dict
end

function Base.setindex!(node::OptiNode, value::Any, t::Tuple{Plasmo.OptiNode, Symbol})
    node.source_graph.node_obj_dict[t] = value
end

struct NodeVariableRef <: JuMP.AbstractVariableRef
    node::OptiNode
    index::MOI.VariableIndex
end
Base.broadcastable(vref::NodeVariableRef) = Ref(vref)
function Base.string(vref::NodeVariableRef)
    return JuMP.name(vref)
end
Base.print(io::IO, vref::NodeVariableRef) = Base.print(io, Base.string(vref))
Base.show(io::IO, vref::NodeVariableRef) = Base.print(io, vref)

# struct NodeConstraintRef
#     node::OptiNode
#     index::MOI.ConstraintIndex
# end
# Base.broadcastable(c::NodeConstraintRef) = Ref(c)

function JuMP.backend(node::OptiNode)
    return backend(node.source_graph.backend)
end

function contained_optigraphs(node::OptiNode)
    source_graph = node.source_graph
    if haskey(source_graph.node_to_graphs, node)
        return source_graph.node_to_graphs[node]
    else
        return OptiGraph[]
    end
end

### OptiEdge

struct OptiEdge{GT<:AbstractOptiGraph} <: JuMP.AbstractModel
    source_graph::GT
    label::String
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

    node_to_graphs::OrderedDict{OptiNode,Vector{OptiGraph}}     # track node membership in other graphs; nodes use this to query different backends
    node_var_idx::OrderedDict{OptiNode,Int64}

    backend::MOI.ModelLike

    # objects on nodes
    node_obj_dict::OrderedDict{Tuple{OptiNode,Symbol},Any}
    obj_dict::Dict{Symbol,Any}
    ext::Dict{Symbol,Any}      # extension information

    #Constructor
    function OptiGraph()
        optigraph = new()
        optigraph.optinodes = Vector{OptiNode}()
        optigraph.optiedges = Vector{OptiEdge}()
        optigraph.subgraphs = Vector{OptiGraph}()

        optigraph.node_to_graphs = OrderedDict{OptiNode,Vector{OptiGraph}}()

        # we put indices here because OptiNode is not mutable
        optigraph.node_var_idx = OrderedDict{OptiNode,Int64}()
        optigraph.node_obj_dict = OrderedDict{Tuple{OptiNode,Symbol},Any}()

        #optigraph.node_data = OrderedDict{OptiNode,NodeData}()
        optigraph.backend = GraphMOIBackend(optigraph)
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

# TODO: PR for JuMP on name_to_register. This lets us overrride how objects get registered in OptiGraphs
function JuMP.name_to_register(node::OptiNode, name::Symbol)
    return (node,name)
end

### Add Node

function add_node(graph::OptiGraph; label::String="n$(length(graph.optinodes) + 1)")
    optinode = OptiNode{OptiGraph}(graph, label) # , Dict{Symbol,Any}()
    push!(graph.optinodes, optinode)
    graph.node_var_idx[optinode] = 0
    return optinode
end

### Variables

function next_variable_index(node::OptiNode)
    return MOI.VariableIndex(num_variables(node) + 1)
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
    
    # increment_variable_index!(node)
    
    if !isempty(name) && MOI.supports(JuMP.backend(node), MOI.VariableName(), MOI.VariableIndex)
        JuMP.set_name(vref, "$(node.label).$(name)")
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

function JuMP.name(vref::NodeVariableRef)
    gb = vref.node.source_graph.backend
    return MOI.get(JuMP.backend(vref.node), MOI.VariableName(), gb.node_to_graph_map[vref])
end

function JuMP.set_name(vref::NodeVariableRef, s::String)
    gb = vref.node.source_graph.backend
    MOI.set(JuMP.backend(vref.node), MOI.VariableName(), gb.node_to_graph_map[vref], s)
    return
end

function JuMP.num_variables(node::OptiNode)
    n2g = node.source_graph.backend.node_to_graph_map
    return length(filter((vref) -> vref.node == node, keys(n2g.var_map)))
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

### Constraints

const NodeConstraintRef = JuMP.ConstraintRef{OptiNode,MOI.ConstraintIndex,S where S <: JuMP.AbstractShape} 

function next_constraint_index(
    node::OptiNode, 
    ::Type{F}, 
    ::Type{S}
) where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    index = num_constraints(node, F, S)
    return MOI.ConstraintIndex{F,S}(index + 1)
end

function JuMP.num_constraints(
    node::OptiNode,
    ::Type{F}, 
    ::Type{S}
)::Int64 where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    return MOI.get(JuMP.backend(node), MOI.NumberOfConstraints{F,S}())
end

"""
    JuMP.add_constraint(node::OptiNode, con::JuMP.AbstractConstraint, base_name::String="")

Add a constraint `con` to optinode `node`. This function supports use of the @constraint JuMP macro.
"""
function JuMP.add_constraint(
    node::OptiNode, con::JuMP.AbstractConstraint, name::String=""
)
    # TODO: determine whether `model_convert` is necessary
    con = JuMP.model_convert(node, con)
    func, set = moi_function(con), moi_set(con)
    constraint_index = next_constraint_index(node, typeof(func), typeof(set))
    cref = NodeConstraintRef(node, constraint_index, JuMP.shape(con))
    _moi_add_node_constraint(cref, func, set)  
    return cref
end

function MOI.ScalarAffineFunction(
    a::GenericAffExpr{C,<:NodeVariableRef},
) where {C}
    _assert_isfinite(a)
    terms = MOI.ScalarAffineTerm{C}[
        MOI.ScalarAffineTerm(t[1], index(t[2])) for t in linear_terms(a)
    ]
    return MOI.ScalarAffineFunction(terms, a.constant)
end

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

# copied from from: https://github.com/jump-dev/JuMP.jl/blob/master/src/variables.jl
function _moi_add_node_constraint(
    cref::NodeConstraintRef,
    func::F,
    set::S,
) where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    node = cref.model
    graph_index = MOI.add_constraint(node.source_graph.backend, cref, func, set)
    for graph in contained_optigraphs(node)
        graph_index = MOI.add_constraint(graph.backend, cref, func, set)
    end
    return nothing
end

function MOI.get(node::OptiNode, attr::MOI.AbstractConstraintAttribute, ref::ConstraintRef)
    return MOI.get(JuMP.backend(node), attr, ref.index)
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




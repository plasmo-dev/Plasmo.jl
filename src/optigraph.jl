mutable struct OptiGraph <: AbstractOptiGraph
    label::Symbol

    # topology
    optinodes::Vector{OptiNode}                  #Local optinodes
    optiedges::Vector{OptiEdge}                  #Local optiedges
    subgraphs::Vector{OptiGraph}

    # subgraphs keep a reference to their parent
    parent_graph::Union{Nothing,OptiGraph}

    # it is possible nodes and edges may use a parent graph as their model backend
    optimizer_graph::OptiGraph

    # track node membership in other graphs; nodes use this to query different backends
    node_to_graphs::OrderedDict{OptiNode,Vector{OptiGraph}}
    edge_to_graphs::OrderedDict{OptiEdge,Vector{OptiGraph}}

    # intermediate moi backend that maps graph elements to MOI model
    backend::MOI.ModelLike

    node_obj_dict::OrderedDict{Tuple{OptiNode,Symbol},Any} # object dictionary for nodes
    edge_obj_dict::OrderedDict{Tuple{OptiEdge,Symbol},Any} # object dictionary for edges
    obj_dict::Dict{Symbol,Any}
    ext::Dict{Symbol,Any}

    bridge_types::Set{Any}
    is_model_dirty::Bool

    #Constructor
    function OptiGraph(;name::Symbol=Symbol(:g,gensym()))
        optigraph = new()
        optigraph.optinodes = Vector{OptiNode}()
        optigraph.optiedges = Vector{OptiEdge}()
        optigraph.subgraphs = Vector{OptiGraph}()
        optigraph.parent_graph = nothing
        optigraph.optimizer_graph = optigraph

        optigraph.node_to_graphs = OrderedDict{OptiNode,Vector{OptiGraph}}()
        optigraph.node_obj_dict = OrderedDict{Tuple{OptiNode,Symbol},Any}()
        optigraph.edge_to_graphs = OrderedDict{OptiEdge,Vector{OptiGraph}}()
        optigraph.edge_obj_dict = OrderedDict{Tuple{OptiEdge,Symbol},Any}()

        optigraph.backend = GraphMOIBackend(optigraph)
        optigraph.obj_dict = Dict{Symbol,Any}()
        optigraph.ext = Dict{Symbol,Any}()
        optigraph.label = name

        optigraph.bridge_types = Set{Any}()
        optigraph.is_model_dirty = false 
        return optigraph
    end
end

# JuMP.value_type(::Type{OptiGraph{T}}) where {T} = T

function graph_backend(graph::OptiGraph)
    return graph.backend
end

function Base.string(graph::OptiGraph)
    return "OptiGraph" * " " * string(graph.label)
end
Base.print(io::IO, graph::OptiGraph) = Base.print(io, Base.string(graph))
Base.show(io::IO, graph::OptiGraph) = Base.print(io, graph)

function JuMP.backend(graph::OptiGraph)
    return graph_backend(graph).moi_backend
end

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

function JuMP.index(graph::OptiGraph, vref::NodeVariableRef)
    gb = graph_backend(graph)
    return gb.node_to_graph_map[vref]
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

### Add subgraph

function add_subgraph(
    graph::OptiGraph; 
    optimizer_graph=graph,
    name::Symbol=Symbol(:sg,gensym())
)
    subgraph = OptiGraph(; name=name)
    subgraph.parent_graph=graph
    # TODO check provided model backend graph
    subgraph.optimizer_graph = optimizer_graph
    push!(graph.subgraphs, subgraph)
    return subgraph
end

### Objective Function

function JuMP.objective_function(
    graph::OptiGraph,
    ::Type{F},
) where {F<:MOI.AbstractFunction}
    func = MOI.get(JuMP.backend(graph), MOI.ObjectiveFunction{F}())::F
    return JuMP.jump_function(graph, func)
end

function JuMP.objective_function(graph::OptiGraph, ::Type{T}) where {T}
    return JuMP.objective_function(graph, JuMP.moi_function_type(T))
end

function JuMP.objective_function(graph::OptiGraph)
    F = MOI.get(JuMP.backend(graph), MOI.ObjectiveFunctionType())
    return JuMP.objective_function(graph, F)
end

function JuMP.set_objective(
    graph::OptiGraph, sense::MOI.OptimizationSense, func::JuMP.AbstractJuMPScalar
)
    JuMP.set_objective_sense(graph, sense)
    JuMP.set_objective_function(graph, func)
    return
end

function JuMP.set_objective_sense(graph::OptiGraph, sense::MOI.OptimizationSense)
    MOI.set(graph_backend(graph), MOI.ObjectiveSense(), sense)
    return
end

function JuMP.set_objective_function(
    graph::OptiGraph, 
    expr::JuMP.GenericAffExpr{C,NodeVariableRef}
) where C <: Real
    _moi_set_objective_function(graph, expr)
    return
end

function JuMP.set_objective_function(
    graph::OptiGraph, 
    expr::JuMP.GenericQuadExpr{C,NodeVariableRef}
) where C <: Real
    _moi_set_objective_function(graph, expr)
    return
end

function JuMP.set_objective_function(
    graph::OptiGraph, 
    expr::JuMP.GenericNonlinearExpr{NodeVariableRef}
) where C <: Real
    _moi_set_objective_function(graph, expr)
    return
end

"""
    JuMP.objective_value(graph::OptiGraph)

Retrieve the current objective value on optigraph `graph`.
"""
function JuMP.objective_value(graph::OptiGraph)
    return MOI.get(backend(graph), MOI.ObjectiveValue())
end


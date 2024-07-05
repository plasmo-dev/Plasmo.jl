#
# get/set attributes
#

function JuMP.get_attribute(
    graph::OptiGraph, attr::AT
) where {AT<:Union{MOI.AbstractModelAttribute,MOI.AbstractOptimizerAttribute}}
    return MOI.get(graph, attr)
end

function JuMP.get_attribute(
    nvref::NodeVariableRef, attr::AT
) where {AT<:MOI.AbstractVariableAttribute}
    return MOI.get(nvref.node, attr, nvref)
end

function JuMP.get_attribute(graph::OptiGraph, name::String)
    return JuMP.get_attribute(graph, MOI.RawOptimizerAttribute(name))
end

# From JuMP: "This method is needed for string types like String15 coming from a DataFrame."
function JuMP.get_attribute(graph::OptiGraph, name::AbstractString)
    return JuMP.get_attribute(graph, String(name))
end

function JuMP.set_attribute(graph::OptiGraph, attr::MOI.AbstractModelAttribute, value::Any)
    MOI.set(graph, attr, value)
    return nothing
end

# NOTE: ConstraintRef covered by JuMP
function JuMP.set_attribute(
    nvref::NodeVariableRef, attr::MOI.AbstractVariableAttribute, value::Any
)
    MOI.set(nvref.node, attr, nvref, value)
    return nothing
end

function JuMP.set_attribute(
    graph::OptiGraph, attr::MOI.AbstractOptimizerAttribute, value::Any
)
    MOI.set(graph, attr, value)
    return nothing
end

function JuMP.set_attribute(graph::OptiGraph, name::String, value)
    JuMP.set_attribute(graph, MOI.RawOptimizerAttribute(name), value)
    return nothing
end

function JuMP.set_attribute(graph::OptiGraph, name::AbstractString, value)
    JuMP.set_attribute(graph, String(name), value)
    return nothing
end

function JuMP.set_attributes(destination::Union{OptiGraph,NodeVariableRef}, pairs::Pair...)
    for (name, value) in pairs
        JuMP.set_attribute(destination, name, value)
    end
    return nothing
end

#
# set optimizer
#

# NOTE: _moi_mode copied from JuMP.jl
# https://github.com/jump-dev/JuMP.jl/blob/301d46e81cb66c74c6e22cd89fb89ced740f157b/src/JuMP.jl#L571-L575
_moi_mode(::MOI.ModelLike) = DIRECT
function _moi_mode(model::MOIU.CachingOptimizer)
    return model.mode == MOIU.AUTOMATIC ? AUTOMATIC : MANUAL
end

function JuMP.mode(graph::OptiGraph)
    return _moi_mode(JuMP.backend(graph_backend(graph)))
end

function JuMP.error_if_direct_mode(graph::OptiGraph, func::Symbol)
    if JuMP.mode(graph) == DIRECT
        error("The `$func` function is not supported in DIRECT mode.")
    end
    return nothing
end

function JuMP.set_optimizer(
    graph::OptiGraph, JuMP.@nospecialize(optimizer_constructor); add_bridges::Bool=true
)
    JuMP.error_if_direct_mode(graph, :set_optimizer)
    if add_bridges
        optimizer = MOI.instantiate(optimizer_constructor)#; with_bridge_type = T)
        for BT in graph.bridge_types
            _moi_call_bridge_function(MOI.Bridges.add_bridge, optimizer, BT)
        end
    else
        optimizer = MOI.instantiate(optimizer_constructor)
    end
    return JuMP.set_optimizer(graph_backend(graph), optimizer)
end

# NOTE: _moi_call_bridge_function copied from JuMP.jl
# https://github.com/jump-dev/JuMP.jl/blob/301d46e81cb66c74c6e22cd89fb89ced740f157b/src/JuMP.jl#L678C1-L699C4
function _moi_call_bridge_function(::Function, ::MOI.ModelLike, args...)
    return error(
        "Cannot use bridge if `add_bridges` was set to `false` in the `Model` ",
        "constructor.",
    )
end

function _moi_call_bridge_function(
    f::Function, model::MOI.Bridges.LazyBridgeOptimizer, args...
)
    return f(model, args...)
end

function _moi_call_bridge_function(
    f::Function, model::MOI.Utilities.CachingOptimizer, args...
)
    return _moi_call_bridge_function(f, model.optimizer, args...)
end

# mostly copied from: https://github.com/jump-dev/JuMP.jl/blob/597ef39c97d713929e8a6819908c341b31cbd8aa/src/optimizer_interface.jl#L409
function JuMP.optimize!(
    graph::OptiGraph;
    #ignore_optimize_hook = (graph.optimize_hook === nothing),
    kwargs...,
)
    # TODO: optimize hooks for optigraphs
    # If the user or an extension has provided an optimize hook, call
    # that instead of solving the model ourselves
    # if !ignore_optimize_hook
    #     return model.optimize_hook(model; kwargs...)
    # end

    if !isempty(kwargs)
        error("Unrecognized keyword arguments: $(join([k[1] for k in kwargs], ", "))")
    end
    if JuMP.mode(graph) != DIRECT &&
        MOIU.state(JuMP.backend(graph_backend(graph))) == MOIU.NO_OPTIMIZER
        throw(JuMP.NoOptimizer())
    end

    # check for node objectives when graph objective is empty
    if iszero(objective_function(graph))
        if has_node_objective(graph)
            @warn "The optigraph objective is empty but objectives exist on optinodes. 
            If this is not intended, consider using `set_to_node_objectives(graph)` to 
            set the graph objective function."
        end
    end

    try
        # make sure subgraph elements are tracked in parent graph after solve
        MOI.optimize!(graph_backend(graph))

        # NOTE: we map after the solve because we need better checks on the backend 
        # (i.e. checks that determine whether we need to aggregate the backends)
        _map_subgraph_elements!(graph)
    catch err
        if err isa MOI.UnsupportedAttribute{MOI.NLPBlock}
            error("The solver does not support nonlinear problems")
        else
            rethrow(err)
        end
    end
    graph.is_model_dirty = false
    return nothing
end

### utilities for tracking nodes and edges in subgraphs when optimizing a parent graph.

function _map_subgraph_elements!(graph::OptiGraph)
    for subgraph in local_subgraphs(graph)
        for node in all_nodes(subgraph)
            _track_node_in_graph(graph, node)
        end
        for edge in all_edges(subgraph)
            _track_edge_in_graph(graph, edge)
        end
    end
end

#
# status results
#

### termination status

function JuMP.termination_status(graph::OptiGraph)
    return MOI.get(graph, MOI.TerminationStatus())::MOI.TerminationStatusCode
end

function MOI.get(graph::OptiGraph, attr::MOI.TerminationStatus)
    if graph.is_model_dirty && JuMP.mode(graph) != DIRECT
        return MOI.OPTIMIZE_NOT_CALLED
    end
    return MOI.get(graph_backend(graph), attr)
end

### result_count

function JuMP.result_count(graph::OptiGraph)::Int
    if JuMP.termination_status(graph) == MOI.OPTIMIZE_NOT_CALLED
        return 0
    end
    return MOI.get(graph, MOI.ResultCount())
end

### raw status

function JuMP.raw_status(graph::OptiGraph)
    if MOI.get(graph, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED
        return "optimize not called"
    end
    return MOI.get(graph, MOI.RawStatusString())
end

function MOI.get(graph::OptiGraph, attr::Union{MOI.PrimalStatus,MOI.DualStatus})
    if graph.is_model_dirty && JuMP.mode(graph) != DIRECT
        return MOI.NO_SOLUTION
    end
    return MOI.get(graph_backend(graph), attr)
end

function JuMP.primal_status(graph::OptiGraph; result::Int=1)
    return MOI.get(graph, MOI.PrimalStatus(result))::MOI.ResultStatusCode
end

function JuMP.dual_status(graph::OptiGraph; result::Int=1)
    return MOI.get(graph, MOI.DualStatus(result))::MOI.ResultStatusCode
end

#
# Optinode optimizer
#

function JuMP.set_optimizer(
    node::OptiNode, JuMP.@nospecialize(optimizer_constructor); add_bridges::Bool=true
)
    # determine the graph to use to optimize the node
    if !haskey(source_graph(node).node_graphs, node)
        node_graph = assemble_optigraph(node)
        source_graph(node).node_graphs[node] = node_graph
    else
        node_graph = source_graph(node).node_graphs[node]
    end

    # set objective on node graph
    JuMP.set_objective(node_graph, objective_sense(node), objective_function(node))
    JuMP.set_optimizer(node_graph, optimizer_constructor; add_bridges=add_bridges)
    return node_graph
end

# NOTE: this resets NLP data on every NodePointer, so graph solutions get cleared
# This is currently a known limitation in Plasmo.jl. If you solve a node after a graph,
# it will remove the graph solution.
function JuMP.optimize!(node::OptiNode; kwargs...)
    node_graph = source_graph(node).node_graphs[node]
    JuMP.optimize!(node_graph; kwargs...)
    return nothing
end

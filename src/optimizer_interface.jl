#  Copyright 2021, Jordan Jalving, Yankai Cao, Victor Zavala, and contributors
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at https://mozilla.org/MPL/2.0/.

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

function JuMP.time_limit_sec(graph::OptiGraph)
    return MOI.get(graph, MOI.TimeLimitSec())
end

#
# set optimizer
#

function JuMP.mode(graph::OptiGraph)
    return _moi_mode(JuMP.backend(graph))
end

function MOIU.state(graph)
    return MOIU.state(JuMP.backend(graph))
end

function MOIU.reset_optimizer(
    graph::OptiGraph, optimizer::MOI.AbstractOptimizer, ::Bool=true
)
    MOIU.reset_optimizer(JuMP.backend(graph), optimizer)
    return nothing
end

function MOIU.reset_optimizer(graph::OptiGraph)
    MOIU.reset_optimizer(JuMP.backend(graph))
    return nothing
end

function MOIU.drop_optimizer(graph::OptiGraph)
    MOIU.drop_optimizer(JuMP.backend(graph))
    return nothing
end

function MOIU.attach_optimizer(graph::OptiGraph)
    MOIU.attach_optimizer(JuMP.backend(graph))
    return nothing
end

"""
    JuMP.set_optimizer(
        graph::OptiGraph, 
        JuMP.@nospecialize(optimizer_constructor); 
        add_bridges::Bool=true
    )

Set the optimizer on `graph` by passing an `optimizer_constructor`.
"""
function JuMP.set_optimizer(
    graph::OptiGraph, JuMP.@nospecialize(optimizer_constructor); add_bridges::Bool=true
)
    JuMP.error_if_direct_mode(JuMP.backend(graph), :set_optimizer)
    if add_bridges
        optimizer = MOI.instantiate(optimizer_constructor; with_bridge_type=Float64)
        for BT in graph.bridge_types
            _moi_call_bridge_function(MOI.Bridges.add_bridge, optimizer, BT)
        end
    else
        optimizer = MOI.instantiate(optimizer_constructor)
    end
    return JuMP.set_optimizer(graph_backend(graph), optimizer)
end

# NOTE: _moi_call_bridge_function adapted from JuMP.jl
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

# NOTE: optimize! adapted from JuMP
# https://github.com/jump-dev/JuMP.jl/blob/597ef39c97d713929e8a6819908c341b31cbd8aa/src/optimizer_interface.jl#L409
"""
    JuMP.optimize!(
        graph::OptiGraph;
        kwargs...,
    )

Optimize `graph` using the current set optimizer.
"""
function JuMP.optimize!(
    graph::OptiGraph;
    #ignore_optimize_hook = (graph.optimize_hook === nothing),
    silence_zero_objective_warning = false,
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
    if iszero(objective_function(graph)) && !(silence_zero_objective_warning)
        if has_node_objective(graph)
            @warn """
            The optigraph objective is empty but objectives exist on optinodes. 
            If this is not intended, consider using `set_to_node_objectives(graph)` to 
            set the graph objective function.
            """
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

"""
    JuMP.termination_status(graph::OptiGraph)

Return the solver termination status of `graph` if a solver has been executed.
"""
function JuMP.termination_status(graph::OptiGraph)
    return MOI.get(graph, MOI.TerminationStatus())::MOI.TerminationStatusCode
end

function MOI.get(graph::OptiGraph, attr::MOI.TerminationStatus)
    if graph.is_model_dirty && JuMP.mode(graph) != DIRECT
        return MOI.OPTIMIZE_NOT_CALLED
    end
    return MOI.get(graph_backend(graph), attr)
end

function JuMP.result_count(graph::OptiGraph)::Int
    if JuMP.termination_status(graph) == MOI.OPTIMIZE_NOT_CALLED
        return 0
    end
    return MOI.get(graph, MOI.ResultCount())
end

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

"""
    JuMP.primal_status(graph::OptiGraph; result::Int=1)

Return the primal status of `graph` if a solver has been executed.
"""
function JuMP.primal_status(graph::OptiGraph; result::Int=1)
    return MOI.get(graph, MOI.PrimalStatus(result))::MOI.ResultStatusCode
end

"""
    JuMP.dual_status(graph::OptiGraph; result::Int=1)

Return the dual status of `graph` if a solver has been executed.
"""
function JuMP.dual_status(graph::OptiGraph; result::Int=1)
    return MOI.get(graph, MOI.DualStatus(result))::MOI.ResultStatusCode
end

#
# Optinode optimizer
#

"""
    JuMP.set_optimizer(
        node::OptiNode, 
        JuMP.@nospecialize(optimizer_constructor); 
        add_bridges::Bool=true
    )

Set the optimizer for an optinode.This internally creates a new optigraph that is 
used to optimize the node. Calling this method on a node returns the newly created graph.
"""
function JuMP.set_optimizer(
    node::OptiNode, JuMP.@nospecialize(optimizer_constructor); add_bridges::Bool=true
)
    # determine the graph to use to optimize the node
    source_data = source_graph(node).element_data
    if !haskey(source_data.node_graphs, node)
        node_graph = assemble_optigraph(node)
        source_data.node_graphs[node] = node_graph
    else
        node_graph = source_data.node_graphs[node]
    end

    # set objective on node graph
    JuMP.set_objective(node_graph, objective_sense(node), objective_function(node))
    JuMP.set_optimizer(node_graph, optimizer_constructor; add_bridges=add_bridges)
    return node_graph
end

function JuMP.optimize!(node::OptiNode; kwargs...)
    source_data = source_graph(node).element_data
    node_graph = source_data.node_graphs[node]
    JuMP.optimize!(node_graph; kwargs...)
    return nothing
end

#
# get/set attributes
#

function JuMP.get_attribute(graph::OptiGraph, attr::AT) where 
    AT <: Union{MOI.AbstractModelAttribute, MOI.AbstractOptimizerAttribute}
    return MOI.get(graph, attr)
end

function JuMP.get_attribute(
    nvref::NodeVariableRef,
    attr::AT,
) where AT <: MOI.AbstractVariableAttribute
    return MOI.get(nvref.node, attr, nvref)
end

function JuMP.get_attribute(
    graph::OptiGraph,
    name::String,
)
    return JuMP.get_attribute(graph, MOI.RawOptimizerAttribute(name))
end

# From JuMP: "This method is needed for string types like String15 coming from a DataFrame."
function JuMP.get_attribute(
    graph::OptiGraph,
    name::AbstractString,
)
    return JuMP.get_attribute(graph, String(name))
end

function JuMP.set_attribute(
    graph::OptiGraph,
    attr::MOI.AbstractModelAttribute,
    value::Any
)
    MOI.set(graph, attr, value)
    return
end

# NOTE: ConstraintRef covered by JuMP
function JuMP.set_attribute(
    nvref::NodeVariableRef,
    attr::MOI.AbstractVariableAttribute,
    value::Any
)
    MOI.set(nvref.node, attr, nvref, value)
    return
end

function JuMP.set_attribute(
    graph::OptiGraph,
    attr::MOI.AbstractOptimizerAttribute,
    value::Any
)
    MOI.set(graph, attr, value)
    return
end

function JuMP.set_attribute(
    graph::OptiGraph,
    name::String,
    value,
)
    JuMP.set_attribute(graph, MOI.RawOptimizerAttribute(name), value)
    return
end

function JuMP.set_attribute(
    graph::OptiGraph,
    name::AbstractString,
    value,
)
    JuMP.set_attribute(graph, String(name), value)
    return
end

function JuMP.set_attributes(
    destination::Union{
        OptiGraph,
        NodeVariableRef
    },
    pairs::Pair...,
)
    for (name, value) in pairs
        JuMP.set_attribute(destination, name, value)
    end
    return
end

#
# set optimizer
#

# TODO: call to backend
function JuMP.mode(graph::OptiGraph)
    return JuMP._moi_mode(JuMP.backend(graph))
end

function JuMP.error_if_direct_mode(graph::OptiGraph, func::Symbol)
    if JuMP.mode(graph) == DIRECT
        error("The `$func` function is not supported in DIRECT mode.")
    end
    return
end

function JuMP.set_optimizer(
    graph::OptiGraph,
    JuMP.@nospecialize(optimizer_constructor);
    add_bridges::Bool = true    
)
    JuMP.error_if_direct_mode(graph, :set_optimizer)
    if add_bridges
        optimizer = MOI.instantiate(optimizer_constructor)#; with_bridge_type = T)
        for BT in graph.bridge_types
            # TODO: do not use private method
            JuMP._moi_call_bridge_function(MOI.Bridges.add_bridge, optimizer, BT)
        end
    else
        optimizer = MOI.instantiate(optimizer_constructor)
    end
    # Update the backend to create a new, concretely typed CachingOptimizer
    # using the existing `model_cache`.
    gb = graph_backend(graph)
    gb.moi_backend = MOIU.CachingOptimizer(JuMP.backend(graph).model_cache, optimizer)
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
        error(
            "Unrecognized keyword arguments: $(join([k[1] for k in kwargs], ", "))",
        )
    end
    if JuMP.mode(graph) != DIRECT && MOIU.state(JuMP.backend(graph)) == MOIU.NO_OPTIMIZER
        throw(JuMP.NoOptimizer())
    end
    
    try
        MOI.optimize!(graph_backend(graph))
    catch err
        if err isa MOI.UnsupportedAttribute{MOI.NLPBlock}
            error(
                "The solver does not support nonlinear problems " *
                "(i.e., NLobjective and NLconstraint).",
            )
        else
            rethrow(err)
        end
    end
    graph.is_model_dirty = false
    return
end

function JuMP.set_optimizer(node::OptiNode; kwargs...)
    error("Optinodes currently do not support setting an optimizer. Optimization is now 
        handled through the optigraph. If you wish to optimize a single optinode, 
        you can create a new optigraph using `assemble_optigraph(node)`.")
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

function MOI.get(
    graph::OptiGraph,
    attr::Union{MOI.PrimalStatus,MOI.DualStatus},
)
    if graph.is_model_dirty && JuMP.mode(graph) != DIRECT
        return MOI.NO_SOLUTION
    end
    return MOI.get(graph_backend(graph), attr)
end

function JuMP.primal_status(graph::OptiGraph; result::Int = 1)
    return MOI.get(graph, MOI.PrimalStatus(result))::MOI.ResultStatusCode
end

function JuMP.dual_status(graph::OptiGraph; result::Int = 1)
    return MOI.get(graph, MOI.DualStatus(result))::MOI.ResultStatusCode
end

#
# Optinode Interface
#

function JuMP.set_optimizer(
        node::OptiNode,
        JuMP.@nospecialize(optimizer_constructor);
        add_bridges::Bool = true
    )
    if !haskey(source_graph(node).node_graphs, node)
        node_graph = assemble_optigraph(node)
        source_graph(node).node_graphs[node] = node_graph
    else
        node_graph = source_graph(node).node_graphs[node]
    end
    JuMP.set_optimizer(node_graph, optimizer_constructor; add_bridges=add_bridges)
    return
end

function JuMP.optimize!(node::OptiNode; kwargs...)
    node_graph = source_graph(node).node_graphs[node]
    JuMP.optimize!(node_graph; kwargs...)
    return
end
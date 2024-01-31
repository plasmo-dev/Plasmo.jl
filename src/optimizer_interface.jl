### get/set attributes

function JuMP.get_attribute(graph::OptiGraph, attr::MOI.AbstractModelAttribute)
    return MOI.get(graph, attr)
end

# NOTE: ConstraintRef covered by JuMP
function JuMP.get_attribute(
    nvref::NodeVariableRef,
    attr::MOI.AbstractVariableAttribute,
)
    return MOI.get(JuMP.owner_model(nvref), attr, nvref)
end

function JuMP.get_attribute(
    graph::OptiGraph,
    attr::MOI.AbstractOptimizerAttribute,
)
    return MOI.get(graph, attr)
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
    value,
)
    MOI.set(graph, attr, value)
    return
end

# NOTE: ConstraintRef covered by JuMP
function JuMP.set_attribute(
    nvref::NodeVariableRef,
    attr::MOI.AbstractVariableAttribute,
    value,
)
    MOI.set(JuMP.owner_model(nvref), attr, nvref, value)
    return
end

function JuMP.set_attribute(
    graph::OptiGraph,
    attr::MOI.AbstractOptimizerAttribute,
    value,
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

### set optimizer

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
    _differentiation_backend::MOI.Nonlinear.AbstractAutomaticDifferentiation = MOI.Nonlinear.SparseReverseMode(),
    kwargs...,
)
	# TODO: legacy nlp model (low priority)
    # The nlp_model is not kept in sync, so re-set it here.
    # TODO: Consider how to handle incremental solves.
    # nlp = nonlinear_model(model)
    # if nlp !== nothing
    #     if _uses_new_nonlinear_interface(model)
    #         error(
    #             "Cannot optimize a model which contains the features from " *
    #             "both the legacy (macros beginning with `@NL`) and new " *
    #             "(`NonlinearExpr`) nonlinear interfaces. You must use one or " *
    #             "the other.",
    #         )
    #     end
    #     evaluator = MOI.Nonlinear.Evaluator(
    #         nlp,
    #         _differentiation_backend,
    #         index.(all_variables(model)),
    #     )
    #     MOI.set(model, MOI.NLPBlock(), MOI.NLPBlockData(evaluator))
    # end

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

    if !(_optimizer_has_full_backend(graph))
        aggregate_backends!(graph)
    end

    try
        MOI.optimize!(JuMP.backend(graph))
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

# to do; easier check if we already aggregated
function _optimizer_has_full_backend(graph::OptiGraph)
    if all(sg -> sg.optimizer_graph == graph, graph.subgraphs)
        return true
    else
        return false
    end
end
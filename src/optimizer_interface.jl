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
	# TODO: legacy nlp model
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
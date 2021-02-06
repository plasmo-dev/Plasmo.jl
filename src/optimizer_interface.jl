#Get backends
JuMP.backend(graph::OptiGraph) = graph.moi_backend
JuMP.backend(node::OptiNode) = JuMP.backend(getmodel(node))
JuMP.moi_mode(node_optimizer::NodeOptimizer) = JuMP.moi_mode(node_optimizer.optimizer)

#Extend OptiNode and OptiGraph with MOI interface
MOI.get(node::OptiNode, args...) = MOI.get(getmodel(node), args...)
MOI.set(node::OptiNode, args...) = MOI.set(getmodel(node), args...)
MOI.get(graph::OptiGraph,args...) = MOI.get(JuMP.backend(graph),args...)

#Create an moi backend for an optigraph using the underlying optinodes and optiedges
function _aggregate_backends!(graph::OptiGraph)
    dest = JuMP.backend(graph)
    nodes = all_nodes(graph)
    srces = JuMP.backend.(nodes)
    for src in srces
        idx_map = append_to_backend!(dest, src, false; filter_constraints=nothing)

        #remember idx_map: {src_attribute => dest_attribute}
        _set_idx_map(src,idx_map) #this retains an index map on each src model
    end

    for link in all_linkconstraints(graph)
        _add_link_constraint!(dest,link)
    end

    return nothing
end

#NOTE: Must hit _aggregate_backends! first
function _set_backend_objective(graph::OptiGraph)
    backend = JuMP.backend(graph)
    obj = objective_function(graph)
    nodes = getnodes(obj)
    srces = JuMP.backend.(nodes)
    idx_maps = _get_idx_map.(srces)
    _set_sum_of_objectives!(backend,srces,idx_maps)
end

#Add a LinkConstraint to a MOI backend.  This is used as part of _aggregate_backends!
function _add_link_constraint!(dest::MOI.ModelLike,link::LinkConstraint)
    jump_func = JuMP.jump_function(link)
    moi_func = JuMP.moi_function(link)
    for (i,term) in enumerate(JuMP.linear_terms(jump_func))
        coeff = term[1]
        var = term[2]

        src = JuMP.backend(getnode(var))
        idx_map = Plasmo._get_idx_map(src)

        var_idx = JuMP.index(var)
        dest_idx = idx_map[var_idx]

        moi_func.terms[i] = MOI.ScalarAffineTerm{Float64}(coeff,dest_idx)
    end
    moi_set = JuMP.moi_set(link)

    MOI.add_constraint(dest,moi_func,moi_set)

    return nothing
end

_get_idx_map(optimizer::NodeOptimizer) = optimizer.idx_map
_get_idx_map(node::OptiNode) = _get_idx_map(JuMP.backend(node))
_set_idx_map(optimizer::NodeOptimizer,idx_map::MOIU.IndexMap) = optimizer.idx_map = idx_map
_set_primals(optimizer::NodeOptimizer,primals::OrderedDict) = optimizer.primals = primals
_set_duals(optimizer::NodeOptimizer,duals::OrderedDict) = optimizer.duals = duals

function _populate_node_results!(graph::OptiGraph)
    graph_backend = JuMP.backend(graph)

    nodes = all_nodes(graph)
    srces = JuMP.backend.(nodes)
    idxmaps = _get_idx_map.(nodes)

    for (src,idxmap) in zip(srces,idxmaps)
        vars = MOI.get(src,MOI.ListOfVariableIndices())
        dest_vars = MOI.VariableIndex[idxmap[var] for var in vars]
        con_list = MOI.get(src,MOI.ListOfConstraints())

        cons = MOI.ConstraintIndex[]
        dest_cons = MOI.ConstraintIndex[]
        for FS in con_list
            F = FS[1]
            S = FS[2]
            con = MOI.get(src,MOI.ListOfConstraintIndices{F,S}())
            dest_con = getindex.(Ref(idxmap),con)
            append!(cons,con)
            append!(dest_cons,dest_con)
        end

        primals = OrderedDict(zip(vars,MOI.get(graph_backend,MOI.VariablePrimal(),dest_vars)))
        duals = OrderedDict(zip(cons,MOI.get(graph_backend,MOI.ConstraintDual(),dest_cons)))
        _set_primals(src,primals)
        _set_duals(src,duals)
    end
end

JuMP.optimize!(graph::OptiGraph,optimizer;kwargs...) = error("The optimizer keyword argument is no longer supported. Use `set_optimizer` first, and then `optimize!`.")

#################################
# Optimizer
#################################
"""
    JuMP.set_optimizer(graph::OptiGraph,optimizer_constructor::Any)

Set an optimizer for the optigraph `graph`.
"""
function JuMP.set_optimizer(graph::OptiGraph, optimizer_constructor)
    caching_mode = MOIU.AUTOMATIC
    universal_fallback = MOIU.UniversalFallback(MOIU.Model{Float64}())
    backend = MOIU.CachingOptimizer(universal_fallback,caching_mode)
    optimizer = MOI.instantiate(optimizer_constructor)
    MOIU.reset_optimizer(backend,optimizer)
    graph.moi_backend = backend
    return nothing
end

function JuMP.optimize!(graph::OptiGraph;kwargs...)
    #check optimizer state.  Create new backend if optimize not called
    backend = JuMP.backend(graph)

    #TODO:
    #check backend state. We don't always want to recreate the model.
    #we could check for incremental changes in the node backends and update the graph backend accordingly

    #combine optinode backends
    _aggregate_backends!(graph)

    #NLP data
    if has_nlp_data(graph)
        MOI.set(backend, MOI.NLPBlock(), _create_nlp_block_data(graph))
        optinodes = all_nodes(graph)
        for k=1:length(optinodes)
            if optinodes[k].model.nlp_data !== nothing
                empty!(optinodes[k].model.nlp_data.nlconstr_duals)
            end
        end
    end

    _set_backend_objective(graph)

    try
        MOI.optimize!(backend)
    catch err
        if err isa MOI.UnsupportedAttribute{MOI.NLPBlock}
            error("The solver does not support nonlinear problems " *
                  "(i.e., NLobjective and NLconstraint).")
        else
            rethrow(err)
        end
    end

    #populate optimizer solutions onto node backend
    _populate_node_results!(graph)

    return nothing
end

function JuMP.set_optimizer(node::OptiNode,optimizer_constructor)
    optimizer = MOI.instantiate(optimizer_constructor)
    node.model.moi_backend.optimizer = optimizer
    return nothing
end

function JuMP.optimize!(node::OptiNode;kwargs...)
    #TODO: Check for optimizer
    #TODO: Would it be better to do: JuMP.optimize!(node.model)? This would setup the NLP data
    JuMP.optimize!(node.model;kwargs...)
    #JuMP.set_optimizer(node,optimizer)


    # backend = JuMP.backend(node)
    # MOI.optimize!(backend;kwargs...)
    return nothing
end

function has_nlp_data(graph::OptiGraph)
    return any(node -> (node.nlp_data !== nothing),all_nodes(graph))
end

function _create_nlp_block_data(graph::OptiGraph)
    @assert has_nlp_data(graph)

    bounds = MOI.NLPBoundsPair[]

    has_nl_obj = false
    for node in all_nodes(graph)
        for constr in node.model.nlp_data.nlconstr
            push!(bounds, MOI.NLPBoundsPair(constr.lb, constr.ub))
        end
        if !has_nl_obj && isa(node.nlp_data.nlobj, JuMP._NonlinearExprData)
            has_nl_obj = true
        end
    end
    return MOI.NLPBlockData(bounds,OptiGraphNLPEvaluator(graph),has_nl_obj)
end

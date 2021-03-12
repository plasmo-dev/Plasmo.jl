#Get backends
JuMP.backend(graph::OptiGraph) = graph.moi_backend
JuMP.backend(node::OptiNode) = JuMP.backend(getmodel(node))
JuMP.moi_mode(node_optimizer::NodeOptimizer) = JuMP.moi_mode(node_optimizer.optimizer)

#Extend OptiNode and OptiGraph with MOI interface
MOI.get(node::OptiNode, args...) = MOI.get(getmodel(node), args...)
MOI.set(node::OptiNode, args...) = MOI.set(getmodel(node), args...)
MOI.get(graph::OptiGraph,args...) = MOI.get(JuMP.backend(graph),args...)

#Create an moi backend for an optigraph using the underlying optinodes and optiedges
#TODO: Make sure bridges work.
function _aggregate_backends!(graph::OptiGraph)
    dest = JuMP.backend(graph)
    nodes = all_nodes(graph)
    srces = JuMP.backend.(nodes)
    for src in srces
        idx_map = append_to_backend!(dest, src, false; filter_constraints=nothing)

        #remember idx_map: {src_attribute => dest_attribute}
        _set_idx_map(src,idx_map) #this retains an index map on each src (node) model
    end

    for linkref in all_linkconstraints(graph)
        constraint_index = _add_link_constraint!(dest,JuMP.constraint_object(linkref))
        linkref.optiedge.idx_map[linkref] = constraint_index
    end

    return nothing
end

function _set_graph_objective(graph::OptiGraph)
    if !has_objective(graph) && has_node_objective(graph)
        nodes = all_nodes(graph)
        # node_senses = JuMP.objective_sense.(nodes)
        #need to flip the node sense
        for node in nodes
            if JuMP.objective_sense(node) == MOI.MAX_SENSE
                JuMP.set_objective_sense(node,MOI.MIN_SENSE)
                JuMP.set_objective_function(node,-1*JuMP.objective_function(node))
            end
        end
        #scl = [JuMP.objective_sense(node) == MOI.MAX_SENSE ? -1 : 1 for node in nodes]
        JuMP.set_objective(graph,MOI.MIN_SENSE,sum(objective_function(nodes[i]) for i = 1:length(nodes)))
    end
    return nothing
end

#NOTE: Must hit _aggregate_backends!() first
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

    constraint_index = MOI.add_constraint(dest,moi_func,moi_set)

    return constraint_index
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

    #nodes
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

    #edges (links)
    for linkref in all_linkconstraints(graph)
        edge = JuMP.owner_model(linkref)
        edge.dual_values[linkref.idx] = MOI.get(graph_backend,MOI.ConstraintDual(),edge.idx_map[linkref])
    end

    #Nonlinear duals
    if MOI.NLPBlock() in MOI.get(graph_backend,MOI.ListOfModelAttributesSet())
        nlp_duals = MOI.get(graph_backend,MOI.NLPBlockDual())
        for node in nodes
            if node.nlp_data != nothing
                nl_idx_map = JuMP.backend(node).nl_idx_map
                node.nlp_data.nlconstr_duals = Vector{Float64}(undef,length(node.nlp_data.nlconstr))
                for (src_index,graph_index) in nl_idx_map
                    node.nlp_data.nlconstr_duals[src_index.value] = nlp_duals[graph_index.value]
                end
            end
        end
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
function JuMP.set_optimizer(graph::OptiGraph, optimizer_constructor,bridge_constraints::Bool = true)
    caching_mode = MOIU.AUTOMATIC
    universal_fallback = MOIU.UniversalFallback(MOIU.Model{Float64}())
    backend = MOIU.CachingOptimizer(universal_fallback,caching_mode)
    if bridge_constraints
        optimizer = MOI.instantiate(optimizer_constructor, with_bridge_type=Float64, with_names=false)
        for bridge_type in graph.bridge_types
            JuMP._moi_add_bridge(optimizer, bridge_type)
        end
    else
        optimizer = MOI.instantiate(optimizer_constructor)
    end
    MOIU.reset_optimizer(backend,optimizer)
    graph.moi_backend = backend
    return nothing
end

function JuMP.optimize!(graph::OptiGraph;kwargs...)
    #check optimizer state.  Create new backend if optimize not called
    backend = JuMP.backend(graph)

    if backend.state == MOIU.NO_OPTIMIZER
        error("Please set an optimizer on optigraph before calling optimize!")
    end

    has_nl_obj = has_nl_objective(graph)

    #set graph objective if it's empty and there are node objectives
    if !(has_nl_obj)
        _set_graph_objective(graph)
    end

    #aggregate optinode backends if it is the first optimization call
    #TODO: Incremental changes
    #check backend state. We don't always want to recreate the backend.
    #we could check for incremental changes in the optinode backends and update the graph backend accordingly
    #if MOI.get(backend,MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED
    _aggregate_backends!(graph)
    # #else
    #     #_update_backend(graph) #check for flags for changes (e.g. new )
    # end

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

    if has_nl_obj
        MOI.set(backend,MOI.ObjectiveSense(),MOI.MIN_SENSE)
    else
        _set_backend_objective(graph)
    end

    try
        MOI.optimize!(backend)
    catch err
        if err isa MOI.UnsupportedAttribute{MOI.NLPBlock}
            error("The solver does not support nonlinear problems " *
                  "(i.e., @NLobjective and @NLconstraint).")
        else
            rethrow(err)
        end
    end

    #populate optimizer solutions onto each node backend
    _populate_node_results!(graph)

    return nothing
end

# function JuMP.set_optimizer(node::OptiNode,optimizer_constructor)
#     optimizer = MOI.instantiate(optimizer_constructor)
#     node.model.moi_backend.optimizer = optimizer
#     return nothing
# end
JuMP.set_optimizer(node::OptiNode,optimizer) = JuMP.set_optimizer(getmodel(node),optimizer)

function JuMP.optimize!(node::OptiNode;kwargs...)
    JuMP.optimize!(getmodel(node);kwargs...)
    return nothing
end

function _create_nlp_block_data(graph::OptiGraph)
    @assert has_nlp_data(graph)

    bounds = MOI.NLPBoundsPair[]
    has_nl_obj = false
    for node in all_nodes(graph)
        if node.model.nlp_data !== nothing
            for (i,constr) in enumerate(node.model.nlp_data.nlconstr)
                push!(bounds, MOI.NLPBoundsPair(constr.lb, constr.ub))
                JuMP.backend(node).nl_idx_map[JuMP.NonlinearConstraintIndex(i)] = JuMP.NonlinearConstraintIndex(length(bounds))
            end
            if !has_nl_obj && isa(node.model.nlp_data.nlobj, JuMP._NonlinearExprData)
                has_nl_obj = true
            end
        end
    end
    return MOI.NLPBlockData(bounds,OptiGraphNLPEvaluator(graph),has_nl_obj)
end

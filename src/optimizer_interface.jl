#Get backends
JuMP.backend(graph::OptiGraph) = graph.optimizer
JuMP.backend(node::OptiNode) = JuMP.backend(jump_model(node))
JuMP.backend(edge::OptiEdge) = edge.backend
JuMP.moi_mode(node_optimizer::NodeBackend) = JuMP.moi_mode(node_optimizer.optimizer)

#Extend OptiNode and OptiGraph with MOI interface
MOI.get(node::OptiNode, args...) = MOI.get(jump_model(node), args...)
MOI.set(node::OptiNode, args...) = MOI.set(jump_model(node), args...)
MOI.get(graph::OptiGraph,args...) = MOI.get(JuMP.backend(graph),args...)

_get_idx_map(id::Symbol,backend::NodeBackend) = backend.result_location[id].node_to_optimizer_map
_get_idx_map(id::Symbol,node::OptiNode) = _get_idx_map(id,JuMP.backend(node))
#_set_idx_map(id::Symbol,backend::NodeBackend,idx_map::MOIU.IndexMap) = backend.result_location[id].node_to_optimizer_map = idx_map

#Create an moi backend for an optigraph by aggregating MOI backends of underlying optinodes and optiedges
function _aggregate_backends!(graph::OptiGraph)
    dest = JuMP.backend(graph)
    id = graph.id

    #Set node backends
    for node in all_nodes(graph)
        src = JuMP.backend(node)
        idx_map = append_to_backend!(dest, src, false; filter_constraints=nothing)
        src.result_location[id] = NodePointer(dest,idx_map)
        #_set_idx_map(id,src,idx_map) #remember: idx_map is {src_attribute => dest_attribute}
    end

    #Set edge backends
    for edge in all_edges(graph)
        edge.backend.result_location[id] = EdgePointer(dest)
    end

    for linkref in all_linkconstraints(graph)
        constraint_index = _add_link_constraint!(id,dest,JuMP.constraint_object(linkref))
        linkref.optiedge.backend.result_location[id].edge_to_optimizer_map[linkref] = constraint_index
        #linkref.optiedge.idx_maps[id][linkref] = constraint_index
    end

    return nothing
end

#TODO: update
function empty_backend!(graph::OptiGraph)
    MOI.empty!(JuMP.backend(graph))
    for node in all_nodes(graph)
        src = JuMP.backend(node)
        delete!(src.idx_maps,graph.id)
        delete!(src.nl_idx_maps,graph.id)
    end
    for edge in all_edges(graph)
        delete!(edge.idx_maps,graph.id)
    end

    return nothing
end

#Set the optigraph objective to the sume of the nodes
function _set_graph_objective(graph::OptiGraph)
    if !has_objective(graph) && has_node_objective(graph)
        nodes = all_nodes(graph)
        for node in nodes
            if JuMP.objective_sense(node) == MOI.MAX_SENSE
                JuMP.set_objective_sense(node,MOI.MIN_SENSE)
                JuMP.set_objective_function(node,-1*JuMP.objective_function(node))
            end
        end
        JuMP.set_objective(graph,MOI.MIN_SENSE,sum(objective_function(nodes[i]) for i = 1:length(nodes)))
    end
    return nothing
end

#NOTE: Must hit _aggregate_backends!() first
#Set the backend objective to the graph objective
function _set_backend_objective(graph::OptiGraph)
    graph_backend = JuMP.backend(graph)
    obj = objective_function(graph)

    idx_map = MOIU.IndexMap()
    for (coeff,term) in linear_terms(obj)
        node = getnode(term)
        node_idx_map = backend(node).result_location[graph.id].node_to_optimizer_map
        idx_map[index(term)] = node_idx_map[index(term)]
    end
    dest_obj = moi_function(obj)  #need to fix indices
    _swap_indices!(dest_obj,idx_map)

    MOI.set(graph_backend,MOI.ObjectiveSense(),MOI.MIN_SENSE)
    MOI.set(graph_backend,MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(),dest_obj)
    return nothing
end

#Add a LinkConstraint to the MOI backend.  This is used as part of _aggregate_backends!
function _add_link_constraint!(id::Symbol,dest::MOI.ModelLike,link::LinkConstraint)
    jump_func = JuMP.jump_function(link)
    moi_func = JuMP.moi_function(link)
    for (i,term) in enumerate(JuMP.linear_terms(jump_func))
        coeff = term[1]
        var = term[2]

        src = JuMP.backend(getnode(var))
        idx_map = src.result_location[id].node_to_optimizer_map
        #idx_map = _get_idx_map(id,src)

        var_idx = JuMP.index(var)
        dest_idx = idx_map[var_idx]

        moi_func.terms[i] = MOI.ScalarAffineTerm{Float64}(coeff,dest_idx)
    end
    moi_set = JuMP.moi_set(link)

    constraint_index = MOI.add_constraint(dest,moi_func,moi_set)

    return constraint_index
end

function _set_node_results!(graph::OptiGraph)
    graph_backend = JuMP.backend(graph)
    id = graph.id

    nodes = all_nodes(graph)
    srces = JuMP.backend.(nodes)
    idxmaps = _get_idx_map.(Ref(id),nodes)

    for src in srces
        src.last_solution_id = graph.id
    end

    #edges (links)
    #edges will also point to Graph MOI model
    for linkref in all_linkconstraints(graph)
        edge = JuMP.owner_model(linkref)
        JuMP.backend(edge).last_solution_id = graph.id
        # edge.dual_values[id][linkref.idx] = MOI.get(graph_backend,MOI.ConstraintDual(),edge.idx_maps[id][linkref])
        # edge.last_solution_id = id
    end

    #Set NLP dual solution for node
    #Nonlinear duals #TODO: multiple node solutions with nlp duals
    if MOI.NLPBlock() in MOI.get(graph_backend,MOI.ListOfModelAttributesSet())
        nlp_duals = MOI.get(graph_backend,MOI.NLPBlockDual())
        for node in nodes
            if node.nlp_data != nothing
                src = JuMP.backend(node)
                nl_idx_map = src.result_location[id].nl_node_to_optimizer_map #JuMP.backend(node).nl_idx_maps[id]
                nl_duals = node.nlp_duals[id]
                #node.nlp_data.nlconstr_duals = Vector{Float64}(undef,length(node.nlp_data.nlconstr))
                for (src_index,graph_index) in nl_idx_map
                    nl_duals[src_index.value] = nlp_duals[graph_index.value] # node.nlp_data.nlconstr_duals[src_index.value] = nlp_duals[graph_index.value]
                end
            end
        end
    end
    return nothing
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
    graph.optimizer = backend
    return nothing
end

function JuMP.optimize!(graph::OptiGraph;kwargs...)
    graph_optimizer = JuMP.backend(graph)
    MOI.empty!(graph.optimizer)
    # backend = JuMP.backend(graph)
    # if backend.state == MOIU.NO_OPTIMIZER
    #     error("Please set an optimizer on optigraph before calling optimize! using set_optimizer(graph,optimizer)")
    # end

    has_nl_obj = has_nl_objective(graph)

    #set graph objective if it's empty and there are node objectives
    if !(has_nl_obj)
        _set_graph_objective(graph)
    end

    _aggregate_backends!(graph)
    #TODO: Efficient incremental solves.  We do not have an efficient implementation yet. Try directly updating graph backend by passing MOI.set commands to both optimizer and pointed model
    # if MOI.get(backend,MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED
    #     _aggregate_backends!(graph)
    # else
    #     _update_backend!(graph)
    # end

    #NLP data
    if has_nlp_data(graph)
        MOI.set(graph_optimizer, MOI.NLPBlock(), _create_nlp_block_data(graph))
        # optinodes = all_nodes(graph)
        # for k=1:length(optinodes)
        #     if optinodes[k].model.nlp_data !== nothing
        #         empty!(optinodes[k].model.nlp_data.nlconstr_duals)
        #     end
        # end
    end

    if has_nl_obj #set default sense if there is a nonlinear objective function
        MOI.set(graph_optimizer,MOI.ObjectiveSense(),MOI.MIN_SENSE)
    else
        _set_backend_objective(graph)
    end

    try
        MOI.optimize!(graph_optimizer)
    catch err
        if err isa MOI.UnsupportedAttribute{MOI.NLPBlock}
            error("The solver does not support nonlinear problems " *
                  "(i.e., @NLobjective and @NLconstraint).")
        else
            rethrow(err)
        end
    end

    _set_node_results!(graph)     #populate optimizer solutions onto each node backend
    return nothing
end

function _create_nlp_block_data(graph::OptiGraph)
    @assert has_nlp_data(graph)
    id = graph.id

    bounds = MOI.NLPBoundsPair[]
    has_nl_obj = false
    for node in all_nodes(graph)
        if node.model.nlp_data !== nothing
            src = JuMP.backend(node)
            nl_idx_map = src.result_location[id].nl_node_to_optimizer_map
            for (i,constr) in enumerate(node.model.nlp_data.nlconstr)
                push!(bounds, MOI.NLPBoundsPair(constr.lb, constr.ub))
                nl_idx_map[JuMP.NonlinearConstraintIndex(i)] = JuMP.NonlinearConstraintIndex(length(bounds))
            end
            if !has_nl_obj && isa(node.model.nlp_data.nlobj, JuMP._NonlinearExprData)
                has_nl_obj = true
            end
        end
    end
    return MOI.NLPBlockData(bounds,OptiGraphNLPEvaluator(graph),has_nl_obj)
end

#OptiNode optimizer.  Hits MOI.optimize!(backend(node))
function JuMP.set_optimizer(node::OptiNode,optimizer)
    JuMP.set_optimizer(jump_model(node),optimizer)
    JuMP.backend(node).last_solution_id = node.id
end

function JuMP.optimize!(node::OptiNode;kwargs...)
    JuMP.optimize!(jump_model(node);kwargs...)
    JuMP.backend(node).result_location[node.id] = JuMP.backend(node).optimizer
    #set nl duals
    return nothing
end

#point each node to the solved MOI model
# for (src,idx_map)
#
# end

#for each optinode
# for (src,idxmap) in zip(srces,idxmaps)
#     #copy variable primals
#     src_vars = MOI.get(src,MOI.ListOfVariableIndices())
#     dest_vars = MOI.VariableIndex[idxmap[var] for var in src_vars]
#     dest_values = MOI.get(graph_backend,MOI.VariablePrimal(),dest_vars)
#     set_node_primals!(src,src_vars,dest_values,id)
#
#     #copy variable duals
#     con_list = MOI.get(src,MOI.ListOfConstraints())
#     src_cons = vcat([MOI.get(src,MOI.ListOfConstraintIndices{FS[1],FS[2]}()) for FS in con_list]...)
#     dest_cons = [getindex(idxmap,src_con) for src_con in src_cons]
#     dest_values = MOI.get(graph_backend,MOI.ConstraintDual(),dest_cons)
#     set_node_duals!(src,src_cons,dest_values,id)
#
#     #set last solution id
#     src.last_solution_id = id
#     src.status = MOI.get(graph_backend,MOI.TerminationStatus())
# end

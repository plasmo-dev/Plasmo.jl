
#Get backends
JuMP.backend(graph::OptiGraph) = graph.moi_backend
JuMP.backend(node::OptiNode) = JuMP.backend(getmodel(node))

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

function _set_sum_of_affine_objectives!(graph::OptiGraph)
    dest = JuMP.backend(graph)
    srces = JuMP.backend.(all_nodes(graph))
    idx_maps = _get_idx_map.(srces)
    _set_sum_of_affine_objectives!(dest,srces,idx_maps)
    return nothing
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

    #combine backends from optinodes
    #TODO: NLP
    _aggregate_backends!(graph)


    # #TODO Set default graph objective function
    # if has_objective(graph)
    #     #use graph objective function
    # else
    _set_sum_of_affine_objectives!(graph)
    # end

    MOI.optimize!(backend)

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
    #JuMP.set_optimizer(node,optimizer)
    backend = JuMP.backend(node)
    MOI.optimize!(backend;kwargs...)
    return nothing
end

#TODO: NLPBlock
# if model.nlp_data !== nothing
#         MOI.set(model, MOI.NLPBlock(), _create_nlp_block_data(model))
#         empty!(model.nlp_data.nlconstr_duals)
# end


# function _copysolution!(optigraph::OptiGraph,ref_map::CombinedMap)
#
#     #Node solutions
#     for node in all_nodes(optigraph)
#         for var in JuMP.all_variables(node)
#             node.variable_values[var] = JuMP.value(ref_map[var])
#         end
#     end
#
#     #Link constraint duals
#     if JuMP.has_duals(ref_map.combined_model)
#         for edge in all_edges(optigraph)
#             for linkcon in getlinkconstraints(edge)
#                 dual = JuMP.dual(ref_map.linkconstraintmap[linkcon])
#                 edge.dual_values[linkcon] = dual
#             end
#         end
#     end
#
#     #TODO Copy constraint duals
#     # for (jnodeconstraint,modelconstraint) in node.constraintmap
#     #     try
#     #         model_node.constraint_dual_values[modelconstraint.index] = JuMP.dual(jnodeconstraint)
#     #     catch ArgumentError #NOTE: Ipopt doesn't catch duals of quadtratic constraints
#     #         continue
#     #     end
#     # end
#     #     for (jnodeconstraint,modelconstraint) in node.nl_constraintmap
#     #         try
#     #             model_node.nl_constraint_dual_values[modelconstraint.index] = JuMP.dual(jnodeconstraint)
#     #         catch ArgumentError #NOTE: Ipopt doesn't catch duals of quadtratic constraints
#     #             continue
#     #         end
#     #     end
#     # end
# end

#has_aggregate(graph::OptiGraph) = haskey(graph.obj_dict,:current_optinode)


#TODO: Equivalent of _moi_get from JuMP
# JuMP.termination_status(graph::OptiGraph) = JuMP.termination_status(getmodel(graph))
# JuMP.raw_status(graph::OptiGraph) = JuMP.raw_status(getmodel(graph))
# JuMP.primal_status(graph::OptiGraph) = JuMP.primal_status(getmodel(graph))
# JuMP.dual_status(graph::OptiGraph) = JuMP.dual_status(getmodel(graph))




# function JuMP.optimize!(graph::OptiGraph;kwargs...)
#     println("Converting OptiGraph to OptiNode...")
#     optinode,reference_map = aggregate(graph)
#
#     println("Optimizing OptiNode")
#     JuMP.set_optimizer(optinode,optimizer)
#     status = JuMP.optimize!(optinode)#,optimizer;kwargs...)
#
#     #Hold on to aggregated optinode and reference map to access solver attributes
#     graph.obj_dict[:current_optinode] = optinode
#     graph.obj_dict[:current_ref_map] = reference_map
#
#     if JuMP.has_values(getmodel(optinode))     # TODO Get all the correct status codes for copying a solution
#         _copysolution!(graph,reference_map)     #Now get our solution data back into the original OptiGraph
#         println("Found Solution")
#     end
#
#     return nothing
# end

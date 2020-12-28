#Convert optigraph into JuMP Model
JuMP.Model(optigraph::OptiGraph;add_node_objectives = !(has_objective(model_graph))) = getmodel(aggregate(optigraph,add_node_objectives = add_node_objectives))

function _aggregate_backends(graph::OptiGraph)
end

# function JuMP.optimize!(graph::OptiGraph,optimizer;kwargs...)
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
#################################
# Optimizer
#################################
"""
    JuMP.set_optimizer(graph::OptiGraph,optimizer::Any)

Set an optimizer for the optigraph `graph`.
"""
#JuMP.set_optimizer(graph::OptiGraph,optimizer) = graph.optimizer = optimizer
#NOTE: Could be a Caching Optimizer or a Direct Optimizer
function set_optimizer(graph::OptiGraph, optimizer_constructor)
    optimizer = MOI.instantiate(optimizer_constructor)
    graph.moi_backend = optimizer
    #MOIU.reset_optimizer(graph, optimizer)
end
# function MOIU.reset_optimizer(model::Model, optimizer::MOI.AbstractOptimizer)
#     error_if_direct_mode(model, :reset_optimizer)
#     MOIU.reset_optimizer(backend(model), optimizer)
# end
#
# function MOIU.reset_optimizer(model::Model)
#     error_if_direct_mode(model, :reset_optimizer)
#     MOIU.reset_optimizer(backend(model))
# end

function JuMP.optimize!(graph::OptiGraph;kwargs...)

    #check optimizer state.  Create new backend if optimize not called

    dest = JuMP.backend(graph)



    #combine backends from optinodes


    #optinode,reference_map = aggregate(graph)


    # status = JuMP.optimize!(optinode)

    #Hold on to aggregated optinode and reference map to access solver attributes


    # if JuMP.has_values(getmodel(optinode))     # TODO Get all the correct status codes for copying a solution
    #     _copysolution!(graph,reference_map)     #Now get our solution data back into the original OptiGraph
    #     println("Found Solution")
    # end

    return nothing
end


# function JuMP.optimize!(graph::OptiGraph,optimizer;kwargs...)
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


function JuMP.optimize!(node::OptiNode,optimizer;kwargs...)
    JuMP.set_optimizer(node,optimizer)
    JuMP.optimize!(getmodel(node);kwargs...)
    return nothing
end



#TODO: Update node_variables
JuMP.optimize!(node::OptiNode;kwargs...) = JuMP.optimize!(getmodel(node);kwargs...)

function _copysolution!(optigraph::OptiGraph,ref_map::CombinedMap)

    #Node solutions
    for node in all_nodes(optigraph)
        for var in JuMP.all_variables(node)
            node.variable_values[var] = JuMP.value(ref_map[var])
        end
    end

    #Link constraint duals
    if JuMP.has_duals(ref_map.combined_model)
        for edge in all_edges(optigraph)
            for linkcon in getlinkconstraints(edge)
                dual = JuMP.dual(ref_map.linkconstraintmap[linkcon])
                edge.dual_values[linkcon] = dual
            end
        end
    end

    #TODO Copy constraint duals
    # for (jnodeconstraint,modelconstraint) in node.constraintmap
    #     try
    #         model_node.constraint_dual_values[modelconstraint.index] = JuMP.dual(jnodeconstraint)
    #     catch ArgumentError #NOTE: Ipopt doesn't catch duals of quadtratic constraints
    #         continue
    #     end
    # end
    #     for (jnodeconstraint,modelconstraint) in node.nl_constraintmap
    #         try
    #             model_node.nl_constraint_dual_values[modelconstraint.index] = JuMP.dual(jnodeconstraint)
    #         catch ArgumentError #NOTE: Ipopt doesn't catch duals of quadtratic constraints
    #             continue
    #         end
    #     end
    # end
end

has_aggregate(graph::OptiGraph) = haskey(graph.obj_dict,:current_optinode)

function getmodel(graph::OptiGraph)
    if has_aggregate(graph)
        return graph.obj_dict[:current_optinode]
    else
        error("OptiGraph has no current aggregate model")
    end
end

JuMP.termination_status(graph::OptiGraph) = JuMP.termination_status(getmodel(graph))
JuMP.raw_status(graph::OptiGraph) = JuMP.raw_status(getmodel(graph))
JuMP.primal_status(graph::OptiGraph) = JuMP.primal_status(getmodel(graph))
JuMP.dual_status(graph::OptiGraph) = JuMP.dual_status(getmodel(graph))

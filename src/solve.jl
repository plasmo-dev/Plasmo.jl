JuMP.Model(optigraph::OptiGraph;add_node_objectives = !(has_objective(model_graph))) = getmodel(aggregate(optigraph,add_node_objectives = add_node_objectives))

function JuMP.optimize!(graph::OptiGraph,optimizer;kwargs...)
    println("Converting OptiGraph to OptiNode...")
    optinode,reference_map = combine(graph)

    println("Optimizing OptiNode")
    JuMP.set_optimizer(optinode,optimizer)
    status = JuMP.optimize!(optinode)#,optimizer;kwargs...)
    #status = JuMP.termination_status(aggregate_model)

    if JuMP.has_values(getmodel(optinode))     # TODO Get all the correct status codes for copying a solution
        _copysolution!(graph,reference_map)     #Now get our solution data back into the original ModelGraph
        println("Found Solution")
    end

    return status
end

function JuMP.optimize!(node::OptiNode,optimizer;kwargs...)
    JuMP.set_optimizer(node,optimizer)
    status = JuMP.optimize!(getmodel(node);kwargs...)
    return status
end

#TODO: Update node_variables
JuMP.optimize!(node::OptiNode;kwargs...) = JuMP.optimize!(getmodel(node);kwargs...)

# function JuMP.optimize!(graph::ModelGraph,optimizer::AbstractModelGraphOptimizer,kwargs...)
#     optimizer_model = initialize_model(optimizer,graph)
#     status = optimize!(optimizer_model)
#     _copysolution!(optimizer_model,graph)
#     return status
# end

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

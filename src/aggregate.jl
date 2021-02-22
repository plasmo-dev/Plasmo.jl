#############################################################################################
# Aggregate: IDEA: Group nodes together into a larger node
#############################################################################################
#############################################################################################
# AggregateMap
#############################################################################################
"""
    AggregateMap
    Mapping between variable and constraint reference of a OptiGraph to an Combined Model.
    The reference of the combined model can be obtained by indexing the map with the reference of the corresponding original optinode.
"""
struct AggregateMap
    optinode::OptiNode
    varmap::Dict{JuMP.VariableRef,JuMP.VariableRef}                 #map variables in original optigraph to optinode
    conmap::Dict{JuMP.ConstraintRef,JuMP.ConstraintRef}             #map constraints in original optigraph to optinode
    linkconstraintmap::Dict{LinkConstraint,JuMP.ConstraintRef}
end

function Base.getindex(reference_map::AggregateMap, vref::JuMP.VariableRef)  #reference_map[node_var] --> combinedd_copy_var
    return reference_map.varmap[vref]
end

function Base.getindex(reference_map::AggregateMap, cref::JuMP.ConstraintRef)
    return reference_map.conmap[cref]
end
Base.broadcastable(reference_map::AggregateMap) = Ref(reference_map)

function Base.setindex!(reference_map::AggregateMap, graph_cref::JuMP.ConstraintRef,node_cref::JuMP.ConstraintRef)
    reference_map.conmap[node_cref] = graph_cref
end

function Base.setindex!(reference_map::AggregateMap, graph_vref::JuMP.VariableRef,node_vref::JuMP.VariableRef)
    reference_map.varmap[node_vref] = graph_vref
end

AggregateMap(node::OptiNode) = AggregateMap(node,Dict{JuMP.VariableRef,JuMP.VariableRef}(),Dict{JuMP.ConstraintRef,JuMP.ConstraintRef}(),Dict{LinkConstraintRef,JuMP.ConstraintRef}())

function Base.merge!(ref_map1::AggregateMap,ref_map2::AggregateMap)
    merge!(ref_map1.varmap,ref_map2.varmap)
    merge!(ref_map1.conmap,ref_map2.conmap)
end


#############################################################################################
# Aggregate Functions
#############################################################################################
"""
    aggregate(graph::OptiGraph)

Aggregate the optigraph `graph` into a new optinode.  Return an optinode and a dictionary which maps optinode variable and
constraint references to the original optigraph.

    aggregate(graph::OptiGraph,max_depth::Int64)

Aggregate the optigraph 'graph' into a new aggregated optigraph. Return a newly aggregated
optigraph and a dictionary which maps new variables and constraints to the original optigraph.
`max_depth` determines how many levels of subgraphs remain in the new aggregated optigraph. For example,
a `max_depth` of `0` signifies there should be no subgraphs in the aggregated optigraph.

"""
function aggregate(optigraph::OptiGraph)
    aggregate_node = OptiNode()
    JuMP.object_dictionary(aggregate_node)[:nodes] = []

    reference_map = AggregateMap(aggregate_node)

    #CHECK OBJECTIVE FORM
    has_nonlinear_objective = has_nl_objective(optigraph)
    if has_nonlinear_objective
        graph_obj = :(0)
    elseif has_quad_objective(optigraph)
        graph_obj = zero(JuMP.GenericQuadExpr{Float64, JuMP.VariableRef})
    else
        graph_obj = zero(JuMP.GenericAffExpr{Float64, JuMP.VariableRef})
    end

    #COPY NODE MODELS INTO AGGREGATE NODE
    for optinode in all_nodes(optigraph)               #for each node in the model graph
        # Need to pass master reference so we use those variables instead of creating new ones
        # node_agg_map = _add_to_aggregate_node!(aggregate_node,optinode,reference_map)  #updates combined_model and reference_map
        _add_to_aggregate_node!(aggregate_node,optinode,reference_map,graph_obj)

        #NOTE:This doesn't seem to work.  I have to pass the reference map to the function for some reason
        #merge!(reference_map,node_agg_map)
    end

    if has_nonlinear_objective
        JuMP.set_NL_objective(aggregate_node,MOI.MIN_SENSE,graph_obj)
    else
        JuMP.set_objective(aggregate_node,MOI.MIN_SENSE,graph_obj)
    end

    #ADD LINK CONSTRAINTS
    for linkconstraint in all_linkconstraints(optigraph)
        new_constraint = _copy_constraint(JuMP.constraint_object(linkconstraint),reference_map)
        cref = JuMP.add_constraint(aggregate_node,new_constraint)
        reference_map.linkconstraintmap[JuMP.constraint_object(linkconstraint)] = cref
    end

    return aggregate_node,reference_map
end
@deprecate combine aggregate
#Modify graph by combining subgraphs
function _add_to_aggregate_node!(aggregate_node::OptiNode,add_node::OptiNode,aggregate_map::AggregateMap,graph_obj::Any)

    reference_map = AggregateMap(aggregate_node)
    constraint_types = JuMP.list_of_constraint_types(add_node)

    #COPY VARIABLES
    for var in JuMP.all_variables(add_node)
        new_x = JuMP.@variable(aggregate_node)   #create an anonymous variable
        reference_map[var] = new_x               #map variable reference to new reference
        var_name = JuMP.name(var)
        new_name = var_name
        JuMP.set_name(new_x,new_name)
        if JuMP.start_value(var) != nothing
            JuMP.set_start_value(new_x,JuMP.start_value(var))
        end
    end

    #COPY  CONSTRAINTS
    for (func,set) in constraint_types
        constraint_refs = JuMP.all_constraints(add_node, func, set)
        for constraint_ref in constraint_refs
            constraint = JuMP.constraint_object(constraint_ref)
            new_constraint = _copy_constraint(constraint,reference_map)
            new_ref= JuMP.add_constraint(aggregate_node,new_constraint)
            reference_map[constraint_ref] = new_ref
            #agg_node.constraintmap[new_ref] = constraint_ref
        end
    end

    #COPY NONLINEAR CONSTRAINTS
    nlp_initialized = false
    if add_node.nlp_data !== nothing
        d = JuMP.NLPEvaluator(add_node)           #Get the NLP evaluator object.  Initialize the expression graph
        MOI.initialize(d,[:ExprGraph])
        nlp_initialized = true
        for i = 1:length(add_node.nlp_data.nlconstr)
            expr = MOI.constraint_expr(d,i)                         #this returns a julia expression
            _splice_nonlinear_variables!(expr,add_node,reference_map)        #splice the variables from var_map into the expression
            new_nl_constraint = JuMP.add_NL_constraint(aggregate_node,expr)      #raw expression input for non-linear constraint
            constraint_ref = JuMP.ConstraintRef(add_node,JuMP.NonlinearConstraintIndex(i),new_nl_constraint.shape)
            reference_map[constraint_ref] = new_nl_constraint
        end
    end

    #ADD TO OBJECTIVE Expression
    if isa(graph_obj,Union{Expr,Int}) #NLP
        if !nlp_initialized
            d = JuMP.NLPEvaluator(add_node)
            MOI.initialize(d,[:ExprGraph])
        end
        new_obj = _copy_nl_objective(d,reference_map)
        graph_obj = Expr(:call,:+,graph_obj,new_obj)  #update graph objective
    else   #AFFINE OR QUADTRATIC OBJECTIVE
        new_objective = _copy_objective(add_node,reference_map)
        sense = JuMP.objective_sense(add_node)
        s = sense == MOI.MAX_SENSE ? -1.0 : 1.0
        JuMP.add_to_expression!(graph_obj,s,new_objective)
    end

    merge!(aggregate_map,reference_map)

    #TODO Get nonlinear object data to work.
    # COPY OBJECT DATA
    node_obj_dict = Dict()
    for (name, value) in JuMP.object_dictionary(add_node)
        #node_obj_dict[name] = reference_map[value]
        node_obj_dict[name] = getindex.(Ref(reference_map),value)
    end
    push!(JuMP.object_dictionary(aggregate_node)[:nodes],node_obj_dict)

    return reference_map, graph_obj
end

#aggregate subgraphs in optigraph to given depth
#TODO: Update for new release
function aggregate(graph::OptiGraph,max_depth::Int64)  #0 means no subgraphs
    println("Aggregating OptiGraph with a maximum subgraph depth of $max_depth")

    sg_dict = Dict()
    root_optigraph = OptiGraph()
    reference_map = AggregateMap(root_optigraph)  #old model graph => new optigraph
    sg_dict[graph] = root_optigraph

    #iterate through depth until we get to last level.  last level is the leaf subgraphs that get converted to nodes
    depth = 0
    parents = [graph]
    final_parents = [graph]
    while depth < max_depth  #maximum subgraph depth.  0 means no subgraphs
        subs_to_check = []
        for parent in parents
            new_parent = sg_dict[parent]
            subs = getsubgraphs(parent)
            for sub in subs
                new_subgraph = OptiGraph()
                add_subgraph!(new_parent,new_subgraph)
                sg_dict[sub] = new_subgraph
            end
            append!(subs_to_check,subs)
        end
        depth += 1
        append!(final_parents,parents)
        parents = subs_to_check
    end

    #ADD THE BOTTOM LEVEL NODES from the corresponding subgraphs
    for parent in parents
        name_idx = 1
        for leaf_subgraph in getsubgraphs(parent)
            combined_node,combine_ref_map = aggregate(leaf_subgraph) #creates new optinode
            merge!(reference_map,combine_ref_map)
            new_parent = sg_dict[parent]
            add_node!(new_parent,combined_node)
            combined_node.label = "$name_idx'"
            name_idx += 1
        end
    end

    #Now add nodes and edges to the higher level graphs
    for graph in reverse(final_parents)  #reverse to start from the bottom
        name_idx = 1

        mnodes = getnodes(graph)
        ledges = getedges(graph)

        new_graph = sg_dict[graph]

        #Add copy optinodes
        for node in mnodes
            new_node,ref_map = _copy_node(node)
            merge!(reference_map,ref_map)
            add_node!(new_graph,new_node)
            new_node.label = "$name_idx'"
            name_idx += 1
        end

        #Add copy linkconstraints
        for optiedge in ledges
            for linkconstraint in getlinkconstraints(optiedge)
                new_con = _copy_constraint(linkconstraint,reference_map)
                JuMP.add_constraint(new_graph,new_con)
            end
        end
    end
    return root_optigraph,reference_map
end

function _copy_node(node::OptiNode)
    new_node = OptiNode()
    reference_map = AggregateMap(new_node)
    node_ref_map = _add_to_combined_model!(new_node,node,reference_map)
    return new_node,reference_map
end



# #Set aggregate objective to sum of node objectives
# function _set_node_objectives!(optigraph::OptiGraph,aggregate_node::OptiNode,reference_map::AggregateMap,has_nonlinear_objective::Bool)
#     if has_nonlinear_objective
#         graph_obj = :(0) #NOTE Strategy: Build up a Julia expression (expr) and then call JuMP.set_NL_objective(expr)
#         for node in all_nodes(optigraph)
#             node_model = getmodel(node)
#             JuMP.objective_sense(node_model) == MOI.MIN_SENSE ? sense = 1 : sense = -1
#             d = JuMP.NLPEvaluator(node_model)
#             MOI.initialize(d,[:ExprGraph])
#             node_obj = MOI.objective_expr(d)
#             _splice_nonlinear_variables!(node_obj,node_model,reference_map)  #_splice_nonlinear_variables!(node_obj,var_maps[node])
#             node_obj = Expr(:call,:*,:($sense),node_obj)
#             graph_obj = Expr(:call,:+,graph_obj,node_obj)  #update graph objective
#         end
#         JuMP.set_NL_objective(aggregate_node.model, MOI.MIN_SENSE, graph_obj)
#     else
#         #TODO: Fix issue with setting maximize
#         graph_obj = sum(JuMP.objective_function(agg_node) for agg_node in getnodes(combined_model))
#         JuMP.set_objective(aggregate_node,MOI.MIN_SENSE,graph_obj)
#     end
# end
#
# function _set_node_objectives!(optigraph::OptiGraph)
#     #check for quadratic objectives
#     if any(isa.(objective_function.(all_nodes(optigraph)),Ref(GenericQuadExpr)))
#         graph_obj = zero(JuMP.GenericQuadExpr{Float64, JuMP.VariableRef})
#     else
#         graph_obj = zero(JuMP.GenericAffExpr{Float64, JuMP.VariableRef})
#     end
#
#     for node in all_nodes(optigraph)
#         sense = JuMP.objective_sense(node)
#         s = sense == MOI.MAX_SENSE ? -1.0 : 1.0
#         JuMP.add_to_expression!(graph_obj,s,JuMP.objective_function(node))
#     end
#
#     JuMP.set_objective(optigraph,MOI.MIN_SENSE,graph_obj)
# end

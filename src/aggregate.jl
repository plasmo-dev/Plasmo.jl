#############################################################################################
# Aggregate: IDEA: Group nodes together into a larger node
#############################################################################################
#TODO: Use MOI to aggregate.  Easier to hit special variable or constraint types
#############################################################################################
# AggregateMap
#############################################################################################
"""
    AggregateMap
    Mapping between variable and constraint reference of a OptiGraph to an Combined Model.
    The reference of the combined model can be obtained by indexing the map with the reference of the corresponding original optinode.
"""
struct AggregateMap
    varmap::Dict{JuMP.VariableRef,JuMP.VariableRef}                 #map variables in original optigraph to optinode
    # TODO: fix printing of nonlinear constraint ref on optinode
    conmap::Dict{JuMP.ConstraintRef,JuMP.ConstraintRef}             #map constraints in original optigraph to optinode
    linkconstraintmap::Dict{LinkConstraint,JuMP.ConstraintRef}
end

function Base.getindex(reference_map::AggregateMap, vref::JuMP.VariableRef)  #reference_map[node_var] --> combinedd_copy_var
    return reference_map.varmap[vref]
end

function Base.getindex(reference_map::AggregateMap, cref::JuMP.ConstraintRef)
    return reference_map.conmap[cref]
end

#NOTE: Quick fix for aggregating object dictionaries
function Base.getindex(reference_map::AggregateMap, value::Any)
    return value
end

Base.broadcastable(reference_map::AggregateMap) = Ref(reference_map)

function Base.setindex!(
    reference_map::AggregateMap,
    graph_cref::JuMP.ConstraintRef,
    node_cref::JuMP.ConstraintRef,
)
    return reference_map.conmap[node_cref] = graph_cref
end

function Base.setindex!(
    reference_map::AggregateMap, graph_vref::JuMP.VariableRef, node_vref::JuMP.VariableRef
)
    return reference_map.varmap[node_vref] = graph_vref
end

# AggregateMap(node::OptiNode) = AggregateMap(node,Dict{JuMP.VariableRef,JuMP.VariableRef}(),Dict{JuMP.ConstraintRef,JuMP.ConstraintRef}(),Dict{LinkConstraintRef,JuMP.ConstraintRef}())

function AggregateMap()
    return AggregateMap(
        Dict{JuMP.VariableRef,JuMP.VariableRef}(),
        Dict{JuMP.ConstraintRef,JuMP.ConstraintRef}(),
        Dict{LinkConstraintRef,JuMP.ConstraintRef}(),
    )
end
function Base.merge!(ref_map1::AggregateMap, ref_map2::AggregateMap)
    merge!(ref_map1.varmap, ref_map2.varmap)
    return merge!(ref_map1.conmap, ref_map2.conmap)
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

    # reference_map = AggregateMap(aggregate_node)
    reference_map = AggregateMap()

    #CHECK OBJECTIVE FORM
    has_nonlinear_objective = has_nl_objective(optigraph)
    if has_nonlinear_objective
        graph_obj = :(0)
    elseif has_node_quad_objective(optigraph)
        graph_obj = zero(JuMP.GenericQuadExpr{Float64,JuMP.VariableRef})
    else
        graph_obj = zero(JuMP.GenericAffExpr{Float64,JuMP.VariableRef})
    end

    #COPY NODE MODELS INTO AGGREGATE NODE
    for optinode in all_nodes(optigraph)
        # Need to pass master reference so we use those variables instead of creating new ones
        # node_agg_map = _add_to_aggregate_node!(aggregate_node,optinode,reference_map)  #updates combined_model and reference_map
        graph_obj = _add_to_aggregate_node!(
            aggregate_node, optinode, reference_map, graph_obj
        )

        #NOTE:This doesn't seem to work.  I have to pass the reference map to the function for some reason
        #merge!(reference_map,node_agg_map)
    end

    if has_nonlinear_objective
        JuMP.set_nonlinear_objective(aggregate_node, MOI.MIN_SENSE, graph_obj)
    else
        JuMP.set_objective(aggregate_node, MOI.MIN_SENSE, graph_obj)
    end

    #ADD LINK CONSTRAINTS
    for linkconstraint in all_linkconstraints(optigraph)
        new_constraint = _copy_constraint(
            JuMP.constraint_object(linkconstraint), reference_map
        )
        cref = JuMP.add_constraint(aggregate_node, new_constraint)
        reference_map.linkconstraintmap[JuMP.constraint_object(linkconstraint)] = cref
    end

    return aggregate_node, reference_map
end
@deprecate combine aggregate

#add optinode model to aggregate optinode model
function _add_to_aggregate_node!(
    aggregate_node::OptiNode,
    add_node::OptiNode,
    aggregate_map::AggregateMap,
    graph_obj::Any,
)

    # reference_map = AggregateMap(aggregate_node)
    reference_map = AggregateMap()
    constraint_types = JuMP.list_of_constraint_types(add_node)

    #COPY VARIABLES
    for var in JuMP.all_variables(add_node)
        new_x = JuMP.@variable(aggregate_node)   #create an anonymous variable
        reference_map[var] = new_x               #map variable reference to new reference
        var_name = JuMP.name(var)
        new_name = var_name
        JuMP.set_name(new_x, new_name)
        if JuMP.start_value(var) != nothing
            JuMP.set_start_value(new_x, JuMP.start_value(var))
        end
    end

    #COPY  CONSTRAINTS
    for (func, set) in constraint_types
        constraint_refs = JuMP.all_constraints(add_node, func, set)
        for constraint_ref in constraint_refs
            constraint = JuMP.constraint_object(constraint_ref)
            new_constraint = _copy_constraint(constraint, reference_map)
            new_ref = JuMP.add_constraint(aggregate_node, new_constraint)
            reference_map[constraint_ref] = new_ref
        end
    end

    #COPY NONLINEAR CONSTRAINTS
    nlp_initialized = false
    nlp = JuMP.nonlinear_model(add_node)
    #if add_node.nlp_data !== nothing
    if nlp != nothing
        #d = JuMP.NLPEvaluator(add_node)   #Get the NLP evaluator object.  Initialize the expression graph
        evaluator = JuMP.NLPEvaluator(
            add_node; _differentiation_backend=MOI.Nonlinear.ExprGraphOnly()
        )
        MOI.initialize(evaluator, [:ExprGraph])
        nlp_initialized = true
        #add_node.nlp_data = add_node.model.nlp_data
        for i in 1:length(nlp.constraints)
            #for i = 1:length(add_node.nlp_data.nlconstr)
            expr = MOI.constraint_expr(evaluator, i)                                  #this returns a julia expression
            _splice_nonlinear_variables!(expr, add_node, reference_map)        #splice the variables from var_map into the expression
            new_nl_constraint = JuMP.add_nonlinear_constraint(aggregate_node, expr)      #raw expression input for non-linear constraint
            constraint_ref = JuMP.ConstraintRef(
                add_node, JuMP.NonlinearConstraintIndex(i), new_nl_constraint.shape
            )
            reference_map[constraint_ref] = new_nl_constraint
        end
    end

    #ADD TO OBJECTIVE Expression
    # if graph objective is a Julia expression
    if isa(graph_obj, Union{Expr,Int})
        if !nlp_initialized
            JuMP._init_NLP(add_node)
            #d = JuMP.NLPEvaluator(add_node)
            evaluator = JuMP.NLPEvaluator(
                add_node; _differentiation_backend=MOI.Nonlinear.ExprGraphOnly()
            )
            MOI.initialize(evaluator, [:ExprGraph])
            #add_node.nlp_data = add_node.model.nlp_data
        end
        new_obj = _copy_nl_objective(add_node, evaluator, reference_map)
        graph_obj = Expr(:call, :+, graph_obj, new_obj)  #update graph objective
    else   #AFFINE OR QUADTRATIC OBJECTIVE
        new_objective = _copy_objective(add_node, reference_map)
        sense = JuMP.objective_sense(add_node)
        s = sense == MOI.MAX_SENSE ? -1.0 : 1.0
        JuMP.add_to_expression!(graph_obj, s, new_objective)
    end

    merge!(aggregate_map, reference_map)

    # COPY OBJECT DATA
    # BUG? The object dictionary can really have anything
    node_obj_dict = Dict()
    for (name, value) in JuMP.object_dictionary(add_node)
        node_obj_dict[name] = getindex.(Ref(reference_map), value)
    end
    push!(JuMP.object_dictionary(aggregate_node)[:nodes], node_obj_dict)

    return graph_obj
end

#aggregate subgraphs in optigraph to given depth
function aggregate(graph::OptiGraph, max_depth::Int64)  #0 means no subgraphs
    println("Aggregating OptiGraph with a maximum subgraph depth of $max_depth")

    sg_dict = Dict()
    root_optigraph = OptiGraph()
    reference_map = AggregateMap()  #old optigraph => new optigraph
    sg_dict[graph] = root_optigraph

    # iterate through depth until we get to last level.
    # last level contains the leaf subgraphs that get converted to optinodes
    depth = 0
    parents = [graph]
    final_parents = [graph]
    while depth < max_depth  #maximum subgraph depth.  0 means no subgraphs
        subs_to_check = []
        for parent in parents
            new_parent = sg_dict[parent]
            subs = subgraphs(parent)
            for sub in subs
                new_subgraph = OptiGraph()
                add_subgraph!(new_parent, new_subgraph)
                sg_dict[sub] = new_subgraph
            end
            append!(subs_to_check, subs)
        end
        depth += 1
        parents = subs_to_check
        append!(final_parents, parents)
    end

    #ADD THE BOTTOM LEVEL NODES from the corresponding subgraphs
    for parent in parents
        name_idx = 1
        for leaf_subgraph in subgraphs(parent)
            #create a new optinode
            combined_node, combine_ref_map = aggregate(leaf_subgraph)
            merge!(reference_map, combine_ref_map)
            new_parent = sg_dict[parent]
            add_node!(new_parent, combined_node)
            combined_node.label = "$name_idx'"
            name_idx += 1
        end
    end

    #Now add nodes and edges to the higher level graphs
    #TODO: I think there is a bug in here when max_depth > 0
    for graph in reverse(final_parents)  #reverse to start from the bottom
        name_idx = 1

        nodes = optinodes(graph)
        edges = optiedges(graph)
        new_graph = sg_dict[graph]

        #Add copy optinodes
        for node in nodes
            new_node, ref_map = _copy_node(node)
            merge!(reference_map, ref_map)
            add_node!(new_graph, new_node)
            new_node.label = "$name_idx'"
            name_idx += 1
        end

        #Add copy linkconstraints
        for edge in edges
            for linkconstraint in linkconstraints(edge)
                new_con = _copy_constraint(linkconstraint, reference_map)
                JuMP.add_constraint(new_graph, new_con)
            end
        end
    end
    return root_optigraph, reference_map
end

"""
    aggregate!(graph::OptiGraph, max_depth::Int64)

Aggregate `graph` by converting subgraphs into optinodes. The `max_depth` determines how many levels of
subgraphs remain in the new aggregated optigraph. For example, a `max_depth` of `0` signifies there should be no subgraphs in
the aggregated optigraph.
"""
function aggregate!(graph::OptiGraph, max_depth::Int64)
    new_graph, ref_map = aggregate(graph, max_depth)
    Base.empty!(graph)

    graph.obj_dict = new_graph.obj_dict
    graph.ext = new_graph.ext
    graph.optinodes = new_graph.optinodes
    graph.optiedges = new_graph.optiedges
    graph.node_idx_map = new_graph.node_idx_map
    graph.edge_idx_map = new_graph.edge_idx_map
    graph.subgraphs = new_graph.subgraphs
    graph.optiedge_map = new_graph.optiedge_map
    graph.objective_sense = new_graph.objective_sense
    graph.objective_function = new_graph.objective_function
    return graph #no reference map
end

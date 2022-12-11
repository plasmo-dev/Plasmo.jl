#Get backends
JuMP.backend(graph::OptiGraph) = graph.moi_backend
JuMP.backend(node::OptiNode) = JuMP.backend(jump_model(node))
JuMP.backend(edge::OptiEdge) = edge.backend
# JuMP.moi_mode(node_optimizer::NodeBackend) = JuMP.moi_mode(node_optimizer.optimizer)

#Extend OptiNode and OptiGraph with MOI interface
MOI.get(node::OptiNode, args...) = MOI.get(jump_model(node), args...)
MOI.set(node::OptiNode, args...) = MOI.set(jump_model(node), args...)
MOI.get(graph::OptiGraph,args...) = MOI.get(JuMP.backend(graph),args...)

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
        JuMP.set_objective(graph, MOI.MIN_SENSE, sum(objective_function(nodes[i]) for i = 1:length(nodes)))
    end
    return nothing
end

#NOTE: Must hit _aggregate_backends!() first
#Set the backend objective to the graph objective
function _set_backend_objective(graph::OptiGraph)
    obj = objective_function(graph)
    _set_backend_objective(graph, obj)
    return nothing
end

function _set_backend_objective(graph::OptiGraph, obj::JuMP.GenericAffExpr{Float64,VariableRef})
    graph_backend = JuMP.backend(graph)
    moi_obj = moi_function(obj)
    for (i,terms) in enumerate(linear_terms(obj))
        term = terms[2]
        moi_term = index(term)
        node = optinode(term)
        node_idx_map = backend(node).optimizers[graph.id].node_to_optimizer_map
        new_moi_idx = node_idx_map[moi_term]
        moi_obj = _swap_linear_term!(moi_obj,i,new_moi_idx)
    end
    MOI.set(graph_backend.optimizer, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.set(graph_backend.optimizer, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), moi_obj)
    return nothing
end

function _set_backend_objective(graph::OptiGraph, obj::JuMP.GenericQuadExpr{Float64,VariableRef})
    graph_backend = JuMP.backend(graph)
    moi_obj = moi_function(obj)
    for (i,terms) in enumerate(quad_terms(obj))
        term1 = terms[2]
        term2 = terms[3]
        node = optinode(term1)
        @assert optinode(term1) == optinode(term2)
        moi_term1 = index(term1)
        moi_term2 = index(term2)
        node_idx_map = backend(node).optimizers[graph.id].node_to_optimizer_map
        new_moi_idx_1 = node_idx_map[moi_term1]
        new_moi_idx_2 = node_idx_map[moi_term2]
        moi_obj = _swap_quad_term!(moi_obj,i,new_moi_idx_1,new_moi_idx_2)
    end

    for (i,terms) in enumerate(linear_terms(obj))
        term = terms[2]
        moi_term = index(term)
        node = optinode(term)
        node_idx_map = backend(node).optimizers[graph.id].node_to_optimizer_map
        new_moi_idx = node_idx_map[moi_term]
        moi_obj = _swap_linear_term!(moi_obj,i,new_moi_idx)
    end

    MOI.set(graph_backend.optimizer, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.set(graph_backend.optimizer, MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}(), moi_obj)
    return nothing
end

function _swap_linear_term!(moi_obj::MOI.ScalarAffineFunction,idx::Int64,new_moi_idx::MOI.VariableIndex)
    term = moi_obj.terms[idx]
    coeff = term.coefficient
    moi_obj.terms[idx] = MOI.ScalarAffineTerm{Float64}(coeff,new_moi_idx)
    return moi_obj
end

function _swap_linear_term!(moi_obj::MOI.ScalarQuadraticFunction,idx::Int64,new_moi_idx::MOI.VariableIndex)
    term = moi_obj.affine_terms[idx]
    coeff = term.coefficient
    moi_obj.affine_terms[idx] = MOI.ScalarAffineTerm{Float64}(coeff,new_moi_idx)
    return moi_obj
end

function _swap_quad_term!(moi_obj::MOI.ScalarQuadraticFunction,idx::Int64,new_moi_idx1::MOI.VariableIndex,new_moi_idx2::MOI.VariableIndex)
    term = moi_obj.quadratic_terms[idx]
    coeff = term.coefficient
    var_idx1 = term.variable_1
    var_idx2 = term.variable_2
    moi_obj.quadratic_terms[idx] = MOI.ScalarQuadraticTerm{Float64}(coeff,new_moi_idx1,new_moi_idx2)
    return moi_obj
end

function _set_node_results!(graph::OptiGraph)
    graph_backend = JuMP.backend(graph)
    id = graph.id

    nodes = all_nodes(graph)
    srces = JuMP.backend.(nodes)
    for src in srces
        src.last_solution_id = graph.id
        src.result_location[id] = src.optimizers[id]
    end

    #edges also point to graph backend model
    for linkref in all_linkconstraints(graph)
        edge = JuMP.owner_model(linkref)
        JuMP.backend(edge).last_solution_id = graph.id
        edge.backend.result_location[id] = edge.backend.optimizers[id]
    end

    #Set NLP dual solution for node
    #Nonlinear duals 
    #TODO: manage node nlp duals on node backend
    #TODO: Add list of model attributes to graph backend.
    #if MOI.NLPBlock() in MOI.get(graph_backend,MOI.ListOfModelAttributesSet())
    try
        nlp_duals = MOI.get(graph_backend, MOI.NLPBlockDual())
        for node in nodes
            if JuMP.nonlinear_model(node) != nothing
            #if node.nlp_data != nothing
                src = JuMP.backend(node)
                nl_idx_map = src.result_location[id].nl_node_to_optimizer_map #JuMP.backend(node).nl_idx_maps[id]
                nl_duals = node.nlp_duals[id]
                for (src_index,graph_index) in nl_idx_map
                    nl_duals[src_index.value] = nlp_duals[graph_index.value] # node.nlp_data.nlconstr_duals[src_index.value] = nlp_duals[graph_index.value]
                end
            end
        end
    catch err
        if !isa(err,MathOptInterface.GetAttributeNotAllowed)
            rethrow(err)
        end
    end
    return nothing
end

function MOIU.attach_optimizer(graph::OptiGraph)
    return MOIU.attach_optimizer(backend(graph))
end

#################################
# Optimizer
#################################
"""
    JuMP.set_optimizer(graph::OptiGraph, optimizer_constructor::Any)

Set an MOI optimizer onto the optigraph `graph`.  Works exactly the same as using JuMP to set an optimizer.

## Example
```julia
graph = OptiGraph()
set_optimizer(graph, GLPK.Optimizer)
```
"""
function JuMP.set_optimizer(graph::OptiGraph,
    optimizer_constructor,
    add_bridges::Bool=true,
    bridge_constraints::Union{Nothing,Bool}=nothing)

    if bridge_constraints != nothing
        @warn(
            "`bridge_constraints` argument is deprecated. Use `add_bridges` instead.")
        add_bridges = bridge_constraints
    end

    if add_bridges
        optimizer = MOI.instantiate(optimizer_constructor, with_bridge_type = Float64)
        for bridge_type in graph.bridge_types
            _moi_add_bridge(optimizer, bridge_type)
        end
    else
        optimizer = MOI.instantiate(optimizer_constructor)
    end

    graph.moi_backend.optimizer = optimizer
    graph.moi_backend.state = MOIU.EMPTY_OPTIMIZER
    return nothing
end

#TODO: support optimize hooks
#TODO: support reseting a new optimizer
"""
    JuMP.optimize!(graph::OptiGraph)

Optimize the optigraph `graph` with the current set optimizer

## Example
```julia
graph = OptiGraph()
set_optimizer(graph, GLPK.Optimizer)
optimize!(graph)
```
"""
function JuMP.optimize!(graph::OptiGraph)
    graph_backend = JuMP.backend(graph)
    if MOIU.state(graph_backend) == MOIU.NO_OPTIMIZER
        error("Please set an optimizer on the optigraph before calling `optimize!` by using `set_optimizer(graph,optimizer)`")
    end

    if graph_backend.state == MOIU.EMPTY_OPTIMIZER
        MOIU.attach_optimizer(graph_backend)
        graph.is_dirty = false
    elseif graph.is_dirty == true
        MOI.empty!(graph_backend.optimizer)
        # MOI.empty!(graph_backend.model_cache)
        graph_backend.state = MOIU.EMPTY_OPTIMIZER
        MOIU.attach_optimizer(graph_backend)
        graph.is_dirty = false
    end

    # Just like JuMP, NLP data is not kept in sync, so set it up here
    if has_nlp_data(graph)
        # NOTE: this also adds the NLPBlock to the graph backend model_cache, not sure we need it there
        MOI.set(graph_backend, MOI.NLPBlock(), _create_nlp_block_data(graph))
    end

    # set objective function
    has_nl_obj = has_nl_objective(graph)
    if !(has_nl_obj)
        # TODO: handle graph objective using GraphBackend instead of setting here
        _set_graph_objective(graph)
        _set_backend_objective(graph) #sets linear or quadratic objective
    else
        #set default sense to minimize if there is a nonlinear objective function
        MOI.set(graph_backend, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    end

    try
        MOI.optimize!(graph_backend)
    catch err
        if err isa MOI.UnsupportedAttribute{MOI.NLPBlock}
            error("The solver does not support nonlinear problems " *
                  "(i.e., @NLobjective and @NLconstraint).")
        else
            rethrow(err)
        end
    end

    #populate solutions onto each node backend
    _set_node_results!(graph)
    for node in all_nodes(graph)
        jump_model(node).is_model_dirty = false
    end
    return nothing
end

_bound(s::MOI.LessThan) = MOI.NLPBoundsPair(-Inf, s.upper)
_bound(s::MOI.GreaterThan) = MOI.NLPBoundsPair(s.lower, Inf)
_bound(s::MOI.EqualTo) = MOI.NLPBoundsPair(s.value, s.value)
_bound(s::MOI.Interval) = MOI.NLPBoundsPair(s.lower, s.upper)

function _create_nlp_block_data(graph::OptiGraph)
    @assert has_nlp_data(graph)
    id = graph.id
    bounds = MOI.NLPBoundsPair[]
    for node in all_nodes(graph)
        nlp = JuMP.nonlinear_model(node)
        if nlp != nothing
            src = JuMP.backend(node)
            nl_idx_map = src.optimizers[id].nl_node_to_optimizer_map
            for (nl_con_idx, constr) in nlp.constraints
                bounds_pair = _bound(constr.set)
                push!(bounds, bounds_pair)
                # update optinode nl constraint map
                # NOTE: the graph backend should have ConstraintIndex consistent with length of bounds
                nl_idx_map[nl_con_idx] = MOI.Nonlinear.ConstraintIndex(length(bounds))
            end
        end
    end
    has_nl_obj = has_nl_objective(graph)
    return MOI.NLPBlockData(bounds, OptiGraphNLPEvaluator(graph), has_nl_obj)
end

#######################################################
#OptiGraph Optimizer Attributes
#######################################################
function JuMP.set_optimizer_attribute(graph::OptiGraph, name::String, value)
    return JuMP.set_optimizer_attribute(graph, MOI.RawOptimizerAttribute(name), value)
end

function JuMP.set_optimizer_attribute(
    graph::OptiGraph,
    attr::MOI.AbstractOptimizerAttribute,
    value)
    return MOI.set(graph, attr, value)
end

function JuMP.get_optimizer_attribute(graph::OptiGraph, name::String)
    return JuMP.get_optimizer_attribute(graph, MOI.RawOptimizerAttribute(name))
end

function JuMP.get_optimizer_attribute(
    graph::OptiGraph,
    attr::MOI.AbstractOptimizerAttribute)
    return MOI.get(graph, attr)
end

function MOI.get(graph::OptiGraph, attr::MOI.AbstractOptimizerAttribute)
    return MOI.get(backend(graph), attr)
end

function MOI.get(graph::OptiGraph, attr::MOI.AbstractModelAttribute)
    return MOI.get(backend(graph), attr)
end

function MOI.set(graph::OptiGraph, attr::MOI.AbstractOptimizerAttribute, value)
    return MOI.set(backend(graph), attr, value)
end

function MOI.set(graph::OptiGraph, attr::MOI.AbstractModelAttribute, value)
    return MOI.set(backend(graph), attr, value)
end


#######################################################
#Optinode optimizer interface
#######################################################
#OptiNode optimizer.  Hits MOI.optimize!(backend(node))
function JuMP.set_optimizer(node::OptiNode, optimizer_constructor)
    JuMP.set_optimizer(jump_model(node), optimizer_constructor)
    JuMP.backend(node).last_solution_id = node.id
    JuMP.backend(node).result_location[node.id] = JuMP.backend(node).optimizer
    return nothing
end

function JuMP.optimize!(node::OptiNode;kwargs...)
    JuMP.optimize!(jump_model(node);kwargs...)
    return nothing
end

function set_node_primals(node::OptiNode, vars::Vector{JuMP.VariableRef}, values::Vector{Float64})
    node_backend = JuMP.backend(node)
    moi_indices = index.(vars)
    set_backend_primals!(node_backend,moi_indices,values,node.id)
    node.model.is_model_dirty = false
    return nothing
end

function set_node_duals(node::OptiNode, cons, values::Vector{Float64})
    node_backend = JuMP.backend(node)
    moi_indices = index.(cons)
    set_backend_duals!(node_backend,moi_indices,values,node.id)
    node.model.is_model_dirty = false
    return nothing
end

function set_node_status(node::OptiNode, status::MOI.TerminationStatusCode)
    node_backend = JuMP.backend(node)
    set_backend_status!(node_backend,status,node.id)
    node.model.is_model_dirty = false
end

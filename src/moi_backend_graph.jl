const ConstraintRefUnion = Union{JuMP.ConstraintRef,LinkConstraintRef}

# maps node/edge variable and constraints to the optigraph backend
mutable struct NodeToGraphMap
    var_map::OrderedDict{JuMP.VariableRef,MOI.VariableIndex}        #node variable to optimizer
    con_map::OrderedDict{ConstraintRefUnion,MOI.ConstraintIndex}    #node constraint to optimizer
end
function NodeToGraphMap()
    return NodeToGraphMap(
        OrderedDict{JuMP.VariableRef,MOI.VariableIndex}(),
        OrderedDict{ConstraintRefUnion,MOI.ConstraintIndex}(),
    )
end

# maps optigraph backend to node/edge
mutable struct GraphToNodeMap
    var_map::OrderedDict{MOI.VariableIndex,JuMP.VariableRef}        #node variable to optimizer
    con_map::OrderedDict{MOI.ConstraintIndex,ConstraintRefUnion}    #node constraint to optimizer
end

function GraphToNodeMap()
    return GraphToNodeMap(
        OrderedDict{MOI.VariableIndex,JuMP.VariableRef}(),
        OrderedDict{MOI.ConstraintIndex,ConstraintRefUnion}(),
    )
end

#acts like a caching optimizer, except it uses references to underlying nodes in the graph
#NOTE: OptiGraph does not support modes yet. Eventually we will
#try to support Direct, Manual, and Automatic modes on an optigraph.
mutable struct GraphBackend{OptimizerType} <: MOI.AbstractOptimizer
    optimizer::Union{Nothing,OptimizerType}
    optigraph::Union{Nothing,AbstractOptiGraph}
    model_cache::MOI.ModelLike
    state::MOIU.CachingOptimizerState
    #mode::MOIU.CachingOptimizerMode #TODO
    model_to_optimizer_map::NodeToGraphMap
    optimizer_to_model_map::GraphToNodeMap
end

"""
    GraphBackend()

Initialize an empty optigraph backend. Contains a model_cache that can be used to set
`MOI.AbstractModelAttribute`s and `MOI.AbstractOptimizerAttribute`s.
"""
function GraphBackend(optigraph::AbstractOptiGraph)
    state = MOIU.NO_OPTIMIZER
    #mode = MOIU.AUTOMATIC # NOTE: modes not yet supported in Plasmo.jl
    model_cache = MOIU.UniversalFallback(MOIU.Model{Float64}())
    return GraphBackend{MOI.AbstractOptimizer}(
        nothing,
        optigraph,
        model_cache,
        state,
        #mode,
        NodeToGraphMap(),
        GraphToNodeMap(),
    )
end

#In MOI this uses lots of `map_indices` magic, but we go for something simple
function MOI.get(graph_backend::GraphBackend, attr::MOI.AbstractModelAttribute)
    #if the attribute is set by the optimizer, query it directly from optimizer
    if MOI.is_set_by_optimize(attr)
        if MOIU.state(graph_backend) == MOIU.NO_OPTIMIZER
            error(
                "Cannot query $(attr) from graph backend because no " *
                "optimizer is attached.",
            )
        end
        return MOI.get(graph_backend.optimizer, attr)
        #otherwise, grab it from the model cache
    else
        return MOI.get(graph_backend.model_cache, attr)
    end
end

function MOI.get(graph_backend::GraphBackend, attr::MOI.AbstractOptimizerAttribute)
    #NOTE: See MOI.CachingOptimizer for dealing with copyable attributes in the future
    if MOIU.state(graph_backend) == MOIU.NO_OPTIMIZER
        error("Cannot query $(attr) from optimizer because no " * "optimizer is attached.")
    end
    return MOI.get(graph_backend.optimizer, attr)
end

function MOI.set(graph_backend::GraphBackend, attr::MOI.AbstractModelAttribute, value)
    #if an optimizer is attached, set the underlying attribute
    if MOIU.state(graph_backend) == MOIU.ATTACHED_OPTIMIZER
        MOI.set(graph_backend.optimizer, attr, value)
    end
    # always set the attribute on the model cache
    MOI.set(graph_backend.model_cache, attr, value)
    return nothing
end

function MOI.set(graph_backend::GraphBackend, attr::MOI.AbstractOptimizerAttribute, value)
    #if an optimizer is attached, set the underlying attribute
    if graph_backend.optimizer != nothing #NOTE: should this be checking MOIU.state?
        MOI.set(graph_backend.optimizer, attr, value)
    end
    MOI.set(graph_backend.model_cache, attr, value)
    return nothing
end

function MOI.get(
    graph_backend::GraphBackend, attr::MOI.VariablePrimalStart, idx::MOI.VariableIndex
)
    return MOI.get(graph_backend.model_cache, attr, idx)
end

#TODO: properly support variable and constraint attributes
#MOI.set(graph_backend::GraphBackend,attr::MOI.AnyAttribute,args...) = MOI.set(graph_backend.optimizer,attr,args...)

MOIU.state(graph_backend::GraphBackend) = graph_backend.state

# TODO: decide whether we support graph modes
#MOIU.mode(graph_backend::GraphBackend) = graph_backend.mode

"""
    append_to_backend!(dest::MOI.ModelLike, src::MOI.ModelLike)

Copy the underylying model from `src` into `dest`, but ignore attributes
such as objective function and objective sense
"""
function append_to_backend!(dest::MOI.ModelLike, src::MOI.ModelLike)
    vis_src = MOI.get(src, MOI.ListOfVariableIndices())   #returns vector of MOI.VariableIndex
    index_map = MOIU.IndexMap()

    # per the comment in MOI:
    # "The `NLPBlock` assumes that the order of variables does not change (#849)
    # Therefore, all VariableIndex and VectorOfVariable constraints are added
    # seprately, and no variables constrained-on-creation are added.""
    # Consequently, Plasmo avoids using the constrained-on-creation approach because
    # of the way it constructs the NLPBlock for the optimizer.

    # has_nlp = MOI.NLPBlock() in MOI.get(src, MOI.ListOfModelAttributesSet())
    # constraints_not_added = if has_nlp
    constraints_not_added = Any[
        MOI.get(src, MOI.ListOfConstraintIndices{F,S}()) for
        (F, S) in MOI.get(src, MOI.ListOfConstraintTypesPresent()) if
        MOIU._is_variable_function(F)
    ]
    # else
    #     Any[
    #         MOIU._try_constrain_variables_on_creation(dest, src, index_map, S)
    #         for S in MOIU.sorted_variable_sets_by_cost(dest, src)
    #     ]
    # end

    # Copy free variables into graph optimizer
    MOI.Utilities._copy_free_variables(dest, index_map, vis_src)

    # Copy variable attributes (e.g. name, and VariablePrimalStart())
    MOI.Utilities.pass_attributes(dest, src, index_map, vis_src)

    # Normally this copies ObjectiveSense() and ObjectiveFunction(), but we don't want to do that here
    #MOI.Utilities.pass_attributes(dest, src, idxmap)

    MOI.Utilities._pass_constraints(dest, src, index_map, constraints_not_added)

    return index_map    #return an idxmap for each source model
end

#Add a LinkConstraint to the MOI backend.  This is used as part of _aggregate_backends!
function _add_link_constraint!(id::Symbol, dest::MOI.ModelLike, link::LinkConstraint)
    jump_func = JuMP.jump_function(link)
    moi_func = JuMP.moi_function(link)
    for (i, term) in enumerate(JuMP.linear_terms(jump_func))
        coeff = term[1]
        var = term[2]

        src = JuMP.backend(optinode(var))
        idx_map = src.optimizers[id].node_to_optimizer_map

        var_idx = JuMP.index(var)
        dest_idx = idx_map[var_idx]

        moi_func.terms[i] = MOI.ScalarAffineTerm{Float64}(coeff, dest_idx)
    end
    moi_set = JuMP.moi_set(link)
    constraint_index = MOI.add_constraint(dest, moi_func, moi_set)
    return constraint_index
end

"""
    MOIU.attach_optimizer(model::GraphBackend)

Populate the underlying optigraph optimizer. Works in a similar way to the
`MOIU.CachingOptimizer`, except it populates using the node and edge models.
"""
function MOIU.attach_optimizer(graph_backend::GraphBackend)
    @assert MOIU.state(graph_backend) == MOIU.EMPTY_OPTIMIZER

    # `dest_optimizer` is the underlying optimizer
    dest_optimizer = graph_backend.optimizer
    optigraph = graph_backend.optigraph

    # copy model and optimizer attributes previously set
    # NOTE: this copies objective function and sense
    if !MOI.is_empty(graph_backend.model_cache)
        MOI.copy_to(dest_optimizer, graph_backend.model_cache)
    end

    id = optigraph.id
    indexmap = NodeToGraphMap()  #node to optimizer
    rindexmap = GraphToNodeMap() #optimizer to nodes

    # copy node backends
    for node in all_nodes(optigraph)
        src = JuMP.backend(node)

        # copy attributes directly to graph optimizer
        idx_map = append_to_backend!(dest_optimizer, src) #node to graph map

        # create a new `NodePointer` that points to this graph optimizer
        # TODO: point to the graph backend instead?
        node_pointer = NodePointer(dest_optimizer, idx_map)
        src.optimizers[id] = node_pointer
        if !(id in src.graph_ids)
            push!(src.graph_ids, id)
        end

        # update index maps
        for (v_src, v_dst) in idx_map.var_map
            var_src = JuMP.VariableRef(node.model, v_src)
            indexmap.var_map[var_src] = v_dst
            rindexmap.var_map[v_dst] = var_src
        end

        for (c_src, c_dst) in idx_map.con_map
            con_src = JuMP.constraint_ref_with_index(node.model, c_src)
            indexmap.con_map[con_src] = c_dst
            rindexmap.con_map[c_dst] = con_src
        end
    end

    # setup edge backends
    for edge in all_edges(optigraph)
        # TODO: point to the graph backend instead?
        edge_pointer = EdgePointer(dest_optimizer)
        edge.backend.result_location[id] = edge_pointer
        edge.backend.optimizers[id] = edge_pointer
    end

    # copy link-constraints to backend
    for linkref in all_linkconstraints(optigraph)
        constraint_index = Plasmo._add_link_constraint!(
            id, dest_optimizer, JuMP.constraint_object(linkref)
        )
        linkref.optiedge.backend.result_location[id].edge_to_optimizer_map[linkref] =
            constraint_index
        indexmap.con_map[linkref] = constraint_index
        rindexmap.con_map[constraint_index] = linkref
    end

    graph_backend.model_to_optimizer_map = indexmap
    graph_backend.optimizer_to_model_map = rindexmap
    graph_backend.state = MOIU.ATTACHED_OPTIMIZER

    #TODO: possibly put the objective function stuff here

    return nothing
end

function MOI.optimize!(graph_backend::GraphBackend)
    # TODO: support modes
    # if graph_backend.mode == MOIU.AUTOMATIC && graph_backend.state == MOIU.EMPTY_OPTIMIZER

    # normally the `attach_optimizer` gets called in a higher scope, but we can attach here for testing purposes
    if MOIU.state(graph_backend) == MOIU.EMPTY_OPTIMIZER
        MOIU.attach_optimizer(graph_backend)
    else
        @assert MOIU.state(graph_backend) == MOIU.ATTACHED_OPTIMIZER
    end
    MOI.optimize!(graph_backend.optimizer)
    return nothing
end

function MOIU.reset_optimizer(graph_backend::GraphBackend)
    MOI.empty!(graph_backend.optimizer)
    # delete graph backend from all nodes
    graph = graph_backend.optigraph
    for node in all_nodes(graph_backend.optigraph)
        nb = JuMP.backend(node)
        filter!(x -> x != graph.id, nb.graph_ids)
        delete!(nb.optimizers, graph.id)
    end
    graph_backend.state = MOIU.EMPTY_OPTIMIZER
    return nothing
end

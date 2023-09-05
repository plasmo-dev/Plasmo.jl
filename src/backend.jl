# const ConstraintRefUnion = Union{JuMP.ConstraintRef,LinkConstraintRef}

# maps node/edge variable and constraints to the optigraph backend
mutable struct NodeToGraphMap
    var_map::OrderedDict{NodeVariableRef,MOI.VariableIndex}        #node variable to optimizer
    con_map::OrderedDict{NodeConstraintRef,MOI.ConstraintIndex}    #node constraint to optimizer
end
function NodeToGraphMap()
    return NodeToGraphMap(
        OrderedDict{NodeVariableRef,MOI.VariableIndex}(),
        OrderedDict{NodeConstraintRef,MOI.ConstraintIndex}(),
    )
end
function Base.setindex!(n2g_map::NodeToGraphMap, idx::MOI.VariableIndex, vref::NodeVariableRef)
    n2g_map.var_map[vref] = idx
    return
end
function Base.getindex(n2g_map::NodeToGraphMap, vref::NodeVariableRef)
    return n2g_map.var_map[vref]
end
function Base.setindex!(n2g_map::NodeToGraphMap, idx::MOI.ConstraintIndex, cref::NodeConstraintRef)
    n2g_map.con_map[cref] = idx
    return
end
function Base.getindex(n2g_map::NodeToGraphMap, cref::NodeConstraintRef)
    return n2g_map.con_map[cref]
end

# maps optigraph backend to node/edge
mutable struct GraphToNodeMap
    var_map::OrderedDict{MOI.VariableIndex,NodeVariableRef}        #node variable to optimizer
    con_map::OrderedDict{MOI.ConstraintIndex,NodeConstraintRef}    #node constraint to optimizer
end

function GraphToNodeMap()
    return GraphToNodeMap(
        OrderedDict{MOI.VariableIndex,NodeVariableRef}(),
        OrderedDict{MOI.ConstraintIndex,NodeConstraintRef}(),
    )
end
function Base.setindex!(g2n_map::GraphToNodeMap,  vref::NodeVariableRef, idx::MOI.VariableIndex)
    g2n_map.var_map[idx] = vref
    return
end
function Base.getindex(g2n_map::GraphToNodeMap, idx::MOI.VariableIndex)
    return g2n_map.var_map[idx]
end
function Base.setindex!(g2n_map::GraphToNodeMap,  cref::NodeConstraintRef, idx::MOI.ConstraintIndex)
    g2n_map.con_map[idx] = cref
    return
end
function Base.getindex(g2n_map::GraphToNodeMap, idx::MOI.ConstraintIndex)
    return g2n_map.con_map[idx]
end

#acts like a caching optimizer, except it uses references to underlying nodes in the graph
#NOTE: OptiGraph does not support modes yet. Eventually we will
#try to support Direct, Manual, and Automatic modes on an optigraph.
mutable struct GraphMOIBackend <: MOI.AbstractOptimizer
    optigraph::AbstractOptiGraph
    # TODO: nlp model
    # nlp_model::MOI.Nonlinear.Model
    moi_backend::MOI.AbstractOptimizer
    node_to_graph_map::NodeToGraphMap
    graph_to_node_map::GraphToNodeMap
end

"""
    GraphMOIBackend()

Initialize an empty optigraph backend. Contains a model_cache that can be used to set
`MOI.AbstractModelAttribute`s and `MOI.AbstractOptimizerAttribute`s.
"""
function GraphMOIBackend(optigraph::AbstractOptiGraph)
    inner = MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}())
    cache = MOI.Utilities.CachingOptimizer(inner, MOI.Utilities.AUTOMATIC)
    return GraphMOIBackend(
        optigraph,
        cache,
        NodeToGraphMap(),
        GraphToNodeMap(),
    )
end

function backend(gb::GraphMOIBackend)
    return gb.moi_backend
end

function MOI.get(graph_backend::GraphMOIBackend, attr::MOI.AnyAttribute)
    return MOI.get(graph_backend.optimizer, attr)
end

function MOI.get(graph_backend::GraphMOIBackend, attr::MOI.AnyAttribute, idx::MOI.Index)
    return MOI.get(graph_backend.optimizer, attr, idx)
end

function MOI.set(graph_backend::GraphMOIBackend, attr::MOI.AnyAttribute, args...)
    MOI.set(graph_backend.optimizer, attr, args...)
end

function MOI.add_variable(graph_backend::GraphMOIBackend, vref::NodeVariableRef)
    graph_index = MOI.add_variable(graph_backend.moi_backend)
    graph_backend.node_to_graph_map[vref] = graph_index
    graph_backend.graph_to_node_map[graph_index] = vref
    return graph_index
end

function MOI.add_constraint(
    graph_backend::GraphMOIBackend,
    cref::NodeConstraintRef,
    func::F,
    set::S,
) where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    graph_index = MOI.add_constraint(graph_backend.moi_backend, func, set)
    graph_backend.node_to_graph_map[cref] = graph_index
    graph_backend.graph_to_node_map[graph_index] = cref
    return graph_index
end

### TODO

function MOI.optimize!(graph_backend::GraphMOIBackend)
    # # TODO: support modes
    # # if graph_backend.mode == MOIU.AUTOMATIC && graph_backend.state == MOIU.EMPTY_OPTIMIZER
    # # normally the `attach_optimizer` gets called in a higher scope, but we can attach here for testing purposes
    # if MOIU.state(graph_backend) == MOIU.EMPTY_OPTIMIZER
    #     MOIU.attach_optimizer(graph_backend)
    # else
    #     @assert MOIU.state(graph_backend) == MOIU.ATTACHED_OPTIMIZER
    # end
    MOI.optimize!(graph_backend.moi_backend)
    return nothing
end


#Helpful utilities
function _swap_indices(variable::MOI.VariableIndex, idxmap::MOIU.IndexMap)
    return idxmap[variable]
end

function _swap_indices(func::MOI.ScalarAffineFunction, idxmap::MOIU.IndexMap)
    new_func = copy(func)
    terms = new_func.terms
    for i in 1:length(terms)
        coeff = terms[i].coefficient
        var_idx = terms[i].variable
        terms[i] = MOI.ScalarAffineTerm{Float64}(coeff, idxmap[var_idx])
    end
    return new_func
end


#In MOI this uses lots of `map_indices` magic, but we go for something simple
# function MOI.get(graph_backend::GraphMOIBackend, attr::MOI.AbstractModelAttribute)
#     #if the attribute is set by the optimizer, query it directly from optimizer
#     if MOI.is_set_by_optimize(attr)
#         if MOIU.state(graph_backend) == MOIU.NO_OPTIMIZER
#             error(
#                 "Cannot query $(attr) from graph backend because no " *
#                 "optimizer is attached.",
#             )
#         end
#         return MOI.get(graph_backend.optimizer, attr)
#     #otherwise, grab it from the model cache
#     else
#         return MOI.get(graph_backend.model_cache, attr)
#     end
# end

# function MOI.set(graph_backend::GraphMOIBackend, attr::MOI.AbstractModelAttribute, value)
#     #if an optimizer is attached, set the underlying attribute
#     if MOIU.state(graph_backend) == MOIU.ATTACHED_OPTIMIZER
#         MOI.set(graph_backend.optimizer, attr, value)
#     end
#     # always set the attribute on the model cache
#     MOI.set(graph_backend.model_cache, attr, value)
#     return nothing
# end

# function MOI.get(graph_backend::GraphMOIBackend, attr::MOI.AbstractOptimizerAttribute)
#     #NOTE: See MOI.CachingOptimizer for dealing with copyable attributes in the future
#     if MOIU.state(graph_backend) == MOIU.NO_OPTIMIZER
#         error("Cannot query $(attr) from optimizer because no " * "optimizer is attached.")
#     end
#     return MOI.get(graph_backend.optimizer, attr)
# end

# function MOI.set(graph_backend::GraphMOIBackend, attr::MOI.AbstractOptimizerAttribute, value)
#     #if an optimizer is attached, set the underlying attribute
#     if graph_backend.optimizer != nothing #NOTE: should this be checking MOIU.state?
#         MOI.set(graph_backend.optimizer, attr, value)
#     end
#     MOI.set(graph_backend.model_cache, attr, value)
#     return nothing
# end

# TODO: properly support variable and constraint attributes
# function MOI.get(
#     graph_backend::GraphMOIBackend, attr::MOI.VariablePrimalStart, idx::MOI.VariableIndex
# )
#     return MOI.get(graph_backend.model_cache, attr, idx)
# end

# MOI.set(graph_backend::GraphMOIBackend,attr::MOI.AnyAttribute,args...) = MOI.set(graph_backend.optimizer,attr,args...)
# MOIU.state(graph_backend::GraphMOIBackend) = graph_backend.state
# MOIU.mode(graph_backend::GraphMOIBackend) = graph_backend.mode

# """
#     append_to_backend!(dest::MOI.ModelLike, src::MOI.ModelLike)

# Copy the underylying model from `src` into `dest`, but ignore attributes
# such as objective function and objective sense
# """
# function append_to_backend!(dest::MOI.ModelLike, src::MOI.ModelLike)
#     vis_src = MOI.get(src, MOI.ListOfVariableIndices())   #returns vector of MOI.VariableIndex
#     index_map = MOIU.IndexMap()

#     # per the comment in MOI:
#     # "The `NLPBlock` assumes that the order of variables does not change (#849)
#     # Therefore, all VariableIndex and VectorOfVariable constraints are added
#     # seprately, and no variables constrained-on-creation are added.""
#     # Consequently, Plasmo avoids using the constrained-on-creation approach because
#     # of the way it constructs the NLPBlock for the optimizer.

#     # has_nlp = MOI.NLPBlock() in MOI.get(src, MOI.ListOfModelAttributesSet())
#     # constraints_not_added = if has_nlp
#     constraints_not_added = Any[
#         MOI.get(src, MOI.ListOfConstraintIndices{F,S}()) for
#         (F, S) in MOI.get(src, MOI.ListOfConstraintTypesPresent()) if
#         MOIU._is_variable_function(F)
#     ]
#     # else
#     #     Any[
#     #         MOIU._try_constrain_variables_on_creation(dest, src, index_map, S)
#     #         for S in MOIU.sorted_variable_sets_by_cost(dest, src)
#     #     ]
#     # end

#     # Copy free variables into graph optimizer
#     MOI.Utilities._copy_free_variables(dest, index_map, vis_src)

#     # Copy variable attributes (e.g. name, and VariablePrimalStart())
#     MOI.Utilities.pass_attributes(dest, src, index_map, vis_src)

#     # Normally this copies ObjectiveSense() and ObjectiveFunction(), but we don't want to do that here
#     #MOI.Utilities.pass_attributes(dest, src, idxmap)

#     MOI.Utilities._pass_constraints(dest, src, index_map, constraints_not_added)

#     return index_map    #return an idxmap for each source model
# end

# #Add a LinkConstraint to the MOI backend.  This is used as part of _aggregate_backends!
# function _add_link_constraint!(id::Symbol, dest::MOI.ModelLike, link::LinkConstraint)
#     jump_func = JuMP.jump_function(link)
#     moi_func = JuMP.moi_function(link)
#     for (i, term) in enumerate(JuMP.linear_terms(jump_func))
#         coeff = term[1]
#         var = term[2]
#         src = JuMP.backend(optinode(var))
#         idx_map = src.optimizers[id].node_to_optimizer_map
#         var_idx = JuMP.index(var)
#         dest_idx = idx_map[var_idx]
#         moi_func.terms[i] = MOI.ScalarAffineTerm{Float64}(coeff, dest_idx)
#     end
#     moi_set = JuMP.moi_set(link)
#     constraint_index = MOI.add_constraint(dest, moi_func, moi_set)
#     return constraint_index
# end



"""
    MOIU.attach_optimizer(model::GraphMOIBackend)

Populate the underlying optigraph optimizer. Works in a similar way to the
`MOIU.CachingOptimizer`, except it populates using the node and edge models.
"""
# function MOIU.attach_optimizer(graph_backend::GraphMOIBackend)
#     @assert MOIU.state(graph_backend) == MOIU.EMPTY_OPTIMIZER

#     # `dest_optimizer` is the underlying MOI optimizer
#     dest_optimizer = graph_backend.optimizer
#     optigraph = graph_backend.optigraph

#     # copy model and optimizer attributes previously set
#     # NOTE: this copies objective function and sense
#     if !MOI.is_empty(graph_backend.model_cache)
#         MOI.copy_to(dest_optimizer, graph_backend.model_cache)
#     end

#     id = optigraph.id
#     indexmap = NodeToGraphMap()  #node to optimizer
#     rindexmap = GraphToNodeMap() #optimizer to nodes

#     # TODO: check for subgraphs to append
#     # copy node backends
#     for node in all_nodes(optigraph)
#         src = JuMP.backend(node)

#         # copy attributes directly to graph optimizer
#         idx_map = append_to_backend!(dest_optimizer, src) #node to graph map

#         # create a new `NodePointer` that points to this graph optimizer
#         # TODO: point to the graph backend instead?
#         node_pointer = NodePointer(dest_optimizer, idx_map)
#         src.optimizers[id] = node_pointer
#         if !(id in src.graph_ids)
#             push!(src.graph_ids, id)
#         end

#         # update index maps
#         for (v_src, v_dst) in idx_map.var_map
#             var_src = JuMP.VariableRef(node.model, v_src)
#             indexmap.var_map[var_src] = v_dst
#             rindexmap.var_map[v_dst] = var_src
#         end

#         for (c_src, c_dst) in idx_map.con_map
#             con_src = JuMP.constraint_ref_with_index(node.model, c_src)
#             indexmap.con_map[con_src] = c_dst
#             rindexmap.con_map[c_dst] = con_src
#         end
#     end

#     # setup edge backends
#     for edge in all_edges(optigraph)
#         edge_pointer = EdgePointer(dest_optimizer)
#         edge.backend.result_location[id] = edge_pointer
#         edge.backend.optimizers[id] = edge_pointer
#     end

#     # copy link-constraints to backend
#     for linkref in all_linkconstraints(optigraph)
#         constraint_index = Plasmo._add_link_constraint!(
#             id, dest_optimizer, JuMP.constraint_object(linkref)
#         )
#         linkref.optiedge.backend.result_location[id].edge_to_optimizer_map[linkref] =
#             constraint_index
#         indexmap.con_map[linkref] = constraint_index
#         rindexmap.con_map[constraint_index] = linkref
#     end

#     graph_backend.model_to_optimizer_map = indexmap
#     graph_backend.optimizer_to_model_map = rindexmap
#     graph_backend.state = MOIU.ATTACHED_OPTIMIZER

#     #TODO: possibly put the objective function stuff here

#     return nothing
# end


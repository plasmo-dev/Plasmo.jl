function Base.string(node::OptiNode)
    return string(JuMP.name(node))
end
Base.print(io::IO, node::OptiNode) = Base.print(io, Base.string(node))
Base.show(io::IO, node::OptiNode) = Base.print(io, node)

function Base.setindex!(node::OptiNode, value::Any, name::Symbol)
    t = (node, name)
    source_graph(node).node_obj_dict[t] = value
    return nothing
end

function Base.getindex(node::OptiNode, name::Symbol)
    t = (node, name)
    return source_graph(node).node_obj_dict[t]
end

function JuMP.name(node::OptiNode)
    return node.label.x
end

function JuMP.set_name(node::OptiNode, label::Symbol)
    node.label.x = label
    return nothing
end

"""
    source_graph(node::OptiNode)

Return the optigraph that contains the optinode. This is the optigraph that 
defined said node and stores node object dictionary data.
"""
function source_graph(node::OptiNode)
    return node.source_graph.x
end

function containing_optigraphs(node::OptiNode)
    source = source_graph(node)
    graphs = [source]
    if haskey(source.node_to_graphs, node)
        graphs = [graphs; source.node_to_graphs[node]]
    end
    return graphs
end

function containing_backends(node::OptiNode)
    return graph_backend.(containing_optigraphs(node))
end

"""
    next_variable_index(node::OptiNode)

Return the next variable index that would be created on this node.
"""
function next_variable_index(node::OptiNode)
    return MOI.VariableIndex(JuMP.num_variables(node) + 1)
end

"""
    graph_backend(node::OptiNode)

Return the `GraphMOIBackend` that holds the associated node model attributes
"""
function graph_backend(node::OptiNode)
    return graph_backend(source_graph(node))
end

"""
    Filter the object dictionary for values that belong to node. Keep in mind that 
this function is slow for optigraphs with many nodes.
"""
function node_object_dictionary(node::OptiNode)
    d = JuMP.object_dictionary(node::OptiNode)
    return filter(p -> p.first[1] == node, d)
end

function next_constraint_index(
    node::OptiNode, ::Type{F}, ::Type{S}
)::MOI.ConstraintIndex{F,S} where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    index = MOI.get(graph_backend(node), MOI.NumberOfConstraints{F,S}(), node)
    return MOI.ConstraintIndex{F,S}(index + 1)
end

#
# JuMP Methods
#

function JuMP.object_dictionary(node::OptiNode)
    d = source_graph(node).node_obj_dict
    return d
end

function JuMP.backend(node::OptiNode)
    return JuMP.backend(source_graph(node))
end

### Variables

function JuMP.num_variables(node::OptiNode)
    return MOI.get(graph_backend(node), MOI.NumberOfVariables(), node)
end

function JuMP.all_variables(node::OptiNode)
    gb = graph_backend(node)
    graph_indices = gb.node_variables[node]
    return getindex.(Ref(gb.graph_to_element_map), graph_indices)
end

function JuMP.delete(node::OptiNode, cref::ConstraintRef)
    if node !== JuMP.owner_model(cref)
        error(
            "The constraint reference you are trying to delete does not " *
            "belong to the model.",
        )
    end
    _set_dirty(node)
    MOI.delete(node, cref)
    return nothing
end

### Constraints

"""
    JuMP.add_constraint(node::OptiNode, con::JuMP.AbstractConstraint, name::String="")

Add a constraint `con` to optinode `node`. This function supports use of the @constraint 
JuMP macro.
"""
function JuMP.add_constraint(node::OptiNode, con::JuMP.AbstractConstraint, name::String="")
    con = JuMP.model_convert(node, con)
    cref = _moi_add_node_constraint(node, con)
    return cref
end

function JuMP.add_nonlinear_operator(
    node::OptiNode, dim::Int, f::Function, args::Vararg{Function,N}; name::Symbol=Symbol(f)
) where {N}
    nargs = 1 + N
    if !(1 <= nargs <= 3)
        error(
            "Unable to add operator $name: invalid number of functions " *
            "provided. Got $nargs, but expected 1 (if function only), 2 (if " *
            "function and gradient), or 3 (if function, gradient, and " *
            "hesssian provided)",
        )
    end
    MOI.set(node, MOI.UserDefinedFunction(name, dim), tuple(f, args...))
    registered_name = graph_operator(graph_backend(node), node, name)
    return JuMP.NonlinearOperator(f, registered_name)
end

function _set_dirty(node::OptiNode)
    for graph in containing_optigraphs(node)
        graph.is_model_dirty = true
    end
    return nothing
end

function _moi_add_node_constraint(node::OptiNode, con::JuMP.AbstractConstraint)
    # get moi function and set
    jump_func = JuMP.jump_function(con)
    _check_node_variables(node, jump_func)
    moi_func = JuMP.moi_function(con)
    moi_set = JuMP.moi_set(con)

    # create constraint index and reference
    constraint_index = next_constraint_index(
        node, typeof(moi_func), typeof(moi_set)
    )::MOI.ConstraintIndex{typeof(moi_func),typeof(moi_set)}
    cref = ConstraintRef(node, constraint_index, JuMP.shape(con))

    # add to each containing optigraph
    for graph in containing_optigraphs(node)
        MOI.add_constraint(graph_backend(graph), cref, jump_func, moi_set)
    end
    return cref
end

function _check_node_variables(
    node::OptiNode,
    jump_func::Union{
        NodeVariableRef,JuMP.GenericAffExpr,JuMP.GenericQuadExpr,JuMP.GenericNonlinearExpr
    },
)
    return isempty(setdiff(_extract_variables(jump_func), JuMP.all_variables(node)))
end

### Objective

function JuMP.set_objective(
    node::OptiNode, sense::MOI.OptimizationSense, func::JuMP.AbstractJuMPScalar
)
    # check that all func terms are for this node
    unique(collect_nodes(func)) == [node] || error("Optinode does not own all variables.")
    d = JuMP.object_dictionary(node)
    d[(node, :objective_sense)] = sense
    d[(node, :objective_function)] = func
    return nothing
end

function JuMP.set_objective_function(node::OptiNode, func::JuMP.AbstractJuMPScalar)
    # check that all func terms are for this node
    unique(collect_nodes(func)) == [node] || error("Optinode does not own all variables.")
    d = JuMP.object_dictionary(node)
    d[(node, :objective_function)] = func
    return nothing
end

function JuMP.set_objective_sense(node::OptiNode, sense::MOI.OptimizationSense)
    d = JuMP.object_dictionary(node)
    d[(node, :objective_sense)] = sense
    return nothing
end

function JuMP.objective_function(node::OptiNode)
    return JuMP.object_dictionary(node)[(node, :objective_function)]
end

function JuMP.objective_sense(node::OptiNode)
    return JuMP.object_dictionary(node)[(node, :objective_sense)]
end

function JuMP.objective_value(graph::OptiGraph, node::OptiNode)
    return value(graph, objective_function(node))
end

function has_objective(node::OptiNode)
    return haskey(JuMP.object_dictionary(node), (node, :objective_function))
end

#
# Set a JuMP.Model to an OptiNode
#

"""
    Set a JuMP.Model to `node`. This copies the model data over and does not mutate
the `model` in any way. 
"""
function set_jump_model(node::OptiNode, model::JuMP.Model)
    return _copy_model_to!(node, model)
end
@deprecate set_model set_jump_model

function _copy_model_to!(node::OptiNode, model::JuMP.Model)
    if !(num_variables(node) == 0 && num_constraints(node) == 0)
        error("An optinode must be empty to set a JuMP Model.")
    end
    # get backends
    src = JuMP.backend(model)
    dest = graph_backend(node)
    index_map = MOIU.IndexMap()

    # copy variables
    source_variables = all_variables(model)
    new_vars = NodeVariableRef[]
    for vref in source_variables
        new_variable_index = next_variable_index(node)
        new_vref = NodeVariableRef(node, new_variable_index)
        MOI.add_variable(dest, new_vref)
        index_map[JuMP.index(vref)] = graph_index(new_vref)
    end

    # pass variable attributes
    vis_src = JuMP.index.(source_variables)
    MOIU.pass_attributes(dest.moi_backend, src, index_map, vis_src)

    # copy constraints
    constraint_types = MOI.get(src, MOI.ListOfConstraintTypesPresent())
    for (F, S) in constraint_types
        cis_src = MOI.get(model, MOI.ListOfConstraintIndices{F,S}())
        index_map_FS = index_map[F, S]
        for ci in cis_src
            src_func = MOI.get(JuMP.backend(model), MOI.ConstraintFunction(), ci)
            src_set = MOI.get(JuMP.backend(model), MOI.ConstraintSet(), ci)
            con = JuMP.constraint_object(JuMP.constraint_ref_with_index(model, ci))
            constraint_index = next_constraint_index(node, F, S)

            # new optinode cref
            new_cref = ConstraintRef(node, constraint_index, JuMP.shape(con))
            new_func = MOIU.map_indices(index_map, src_func)
            dest_index = MOI.add_constraint(dest, new_cref, new_func, src_set)
            index_map_FS[ci] = dest_index
        end
        # pass constraint attributes
        MOIU.pass_attributes(dest.moi_backend, src, index_map_FS, cis_src)
    end

    # copy objective to node
    F = JuMP.moi_function_type(JuMP.objective_function_type(model))
    obj_func = MOI.get(JuMP.backend(model), MOI.ObjectiveFunction{F}())
    new_moi_obj_func = MOIU.map_indices(index_map, obj_func)
    new_obj_func = JuMP.jump_function(node, new_moi_obj_func)
    JuMP.set_objective(node, JuMP.objective_sense(model), new_obj_func)
    return nothing
end

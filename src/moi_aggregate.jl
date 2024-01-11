"""
    aggregate_backends!(graph::OptiGraph)

Aggregate the moi backends from each subgraph within `graph` to create a single backend.
"""
function aggregate_backends!(graph::OptiGraph)
    for subgraph in get_subgraphs(graph)
        _aggregate_subgraph_nodes!(subgraph)
        _aggregate_subgraph_edges!(subgraph)
    end
end

function _aggregate_subgraph_nodes!(graph::OptiGraph)
    for node in all_nodes(graph)
        _append_node_to_backend!(graph, node)
    end
end

function _append_node_to_backend!(graph::OptiGraph, node::OptiNode)
    src = graph_backend(node)
    dest = graph_backend(graph)
    index_map = MOIU.IndexMap()

    # copy node variables and variable attributes
    _copy_node_variables(dest, node, index_map)

    # copy constraints and constraint attributes
    # NOTE: for now, we split between variable and non-variable, but they do the same thing
    # eventually, we might try doing something more similar to MOI `default_copy_to` where
    # we try to constraint variables on creation.
    all_constraint_types = MOI.get(node, MOI.ListOfConstraintTypesPresent())
    variable_constraint_types = filter(all_constraint_types) do (F, S)
        return MOIU._is_variable_function(F)
    end
    _copy_node_constraints(
        dest, 
        node,
        index_map, 
        variable_constraint_types
    )

    # copy non-variable constraints
    nonvariable_constraint_types = filter(all_constraint_types) do (F, S)
        return !MOIU._is_variable_function(F)
    end
    _copy_node_constraints(
        dest,
        node,
        index_map,
        nonvariable_constraint_types
    )

    # TODO: pass non-objective attributes (use MOI Filter?)

    return
end

function _copy_node_variables(
    dest::GraphMOIBackend,
    node::OptiNode,
    index_map::MOIU.IndexMap
)
    src = graph_backend(node)
    node_variables = all_variables(node)

    # map existing variables in index_map
    existing_vars = intersect(node_variables, keys(dest.node_to_graph_map.var_map))
    for var in existing_vars
        src_graph_index = graph_index(var)
        dest_graph_index = dest.node_to_graph_map[var]
        index_map[src_graph_index] = dest_graph_index
    end

    # create and add new variables
    vars_to_add = setdiff(node_variables, keys(dest.node_to_graph_map.var_map))
    for var in vars_to_add
        src_graph_index = graph_index(var)
        dest_graph_index = _add_variable_to_backend(dest, var)
        index_map[src_graph_index] = dest_graph_index
    end

    # pass variable attributes
    vis_src = graph_index.(node_variables)
    MOIU.pass_attributes(dest.moi_backend, src.moi_backend, index_map, vis_src)
    return
end

# TODO: update graph backend mappings
function _copy_node_constraints(
    dest::GraphMOIBackend, 
    node::OptiNode,
    index_map::MOIU.IndexMap,
    constraint_types
)
    for (F, S) in constraint_types
        cis_src = MOI.get(node, MOI.ListOfConstraintIndices{F,S}())
        _copy_node_constraints(dest, node, index_map, cis_src)
    end
    
    src = graph_backend(node)
    for (F, S) in constraint_types
        MOIU.pass_attributes(
            dest.moi_backend,
            src.moi_backend,
            index_map,
            MOI.get(node, MOI.ListOfConstraintIndices{F,S}()),
        )
    end
    return
end

function _copy_node_constraints(
    dest::GraphMOIBackend, 
    node::OptiNode, 
    index_map::MOIU.IndexMap, 
    cis_src::Vector{MOI.ConstraintIndex{F,S}}
) where {F,S}
    return _copy_node_constraints(dest, node, index_map, index_map[F, S], cis_src)
end

function _copy_node_constraints(
    dest::GraphMOIBackend,
    node::OptiNode,
    index_map::MOIU.IndexMap,
    index_map_FS,
    cis_src::Vector{<:MOI.ConstraintIndex},
)
    src = graph_backend(node)
    for ci in cis_src
        f = MOI.get(src.moi_backend, MOI.ConstraintFunction(), ci)
        s = MOI.get(src.moi_backend, MOI.ConstraintSet(), ci)
        cref = src.graph_to_node_map[ci]
        dest_index = _add_node_constraint_to_backend(
            dest,
            cref,
            MOIU.map_indices(index_map, f), 
            s
        )
        index_map_FS[ci] = dest_index
    end
    return
end
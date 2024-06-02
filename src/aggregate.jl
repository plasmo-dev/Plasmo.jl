"""
    GraphReferenceMap

Mapping between variable and constraint reference of a OptiGraph to an Combined Model.
The reference of the combined model can be obtained by indexing the map with the 
reference of the corresponding original optinode.
"""
struct GraphReferenceMap
    #map variables in original optigraph to optinode
    var_map::OrderedDict{NodeVariableRef,NodeVariableRef}

    #map constraints in original optigraph to optinode
    con_map::OrderedDict{JuMP.ConstraintRef,JuMP.ConstraintRef}  
end

function Base.getindex(ref_map::GraphReferenceMap, vref::NodeVariableRef)
    return ref_map.var_map[vref]
end

function Base.getindex(ref_map::GraphReferenceMap, cref::JuMP.ConstraintRef)
    return ref_map.con_map[cref]
end

# NOTE: Quick fix for aggregating object dictionaries
function Base.getindex(ref_map::GraphReferenceMap, value::Any)
    return value
end

Base.broadcastable(ref_map::GraphReferenceMap) = Ref(ref_map)

function Base.setindex!(
    ref_map::GraphReferenceMap,
    graph_cref::JuMP.ConstraintRef,
    node_cref::JuMP.ConstraintRef,
)
    return ref_map.con_map[node_cref] = graph_cref
end

function Base.setindex!(
    ref_map::GraphReferenceMap, graph_vref::NodeVariableRef, node_vref::NodeVariableRef
)
    return ref_map.var_map[node_vref] = graph_vref
end

function GraphReferenceMap()
    return GraphReferenceMap(
        Dict{NodeVariableRef,NodeVariableRef}(),
        Dict{JuMP.ConstraintRef,JuMP.ConstraintRef}(),
    )
end
function Base.merge!(ref_map1::GraphReferenceMap, ref_map2::GraphReferenceMap)
    merge!(ref_map1.var_map, ref_map2.var_map)
    return merge!(ref_map1.con_map, ref_map2.con_map)
end

### Aggregate Functions

"""
    aggregate(graph::OptiGraph; return_mapping=true)

Aggregate an optigraph into a graph containing a single optinode.
"""
function aggregate(graph::OptiGraph)
    # aggregate into a graph containing a single node.
    new_graph = OptiGraph()
    new_node, ref_map = _copy_graph_elements_to!(new_graph, graph)

    # pass model attributes
    # copy other model attributes (including objective function)
    # setup index_map from the ref_map
    _copy_attributes_to!(new_graph, graph, ref_map)
    return new_node, ref_map
end

"""
    Copy graph attributes from optigraph `source_graph` to the new optigraph `new_graph`.
"""
function _copy_attributes_to!(
    new_graph::OptiGraph, 
    source_graph::OptiGraph, 
    ref_map::GraphReferenceMap
)
    src = graph_backend(source_graph)
    dest = graph_backend(new_graph)
    index_map = MOIU.IndexMap()

    # NOTE: we use an if statement because the source graph does not necessarily have all 
    # the variables or constraints. we just want to pass the attributes that would be 
    # exposed such as the objective function.
    for (source_vref, dest_vref) in ref_map.var_map
        if source_vref in keys(src.element_to_graph_map.var_map)
            index_map[graph_index(source_graph, source_vref)] = graph_index(dest_vref)
        end
    end
    for (source_cref, dest_cref) in ref_map.con_map
        if source_cref in keys(src.element_to_graph_map.con_map)
            index_map[graph_index(source_graph, source_cref)] = graph_index(dest_cref)
        end
    end
    MOIU.pass_attributes(dest.moi_backend, src.moi_backend, index_map)
    return
end


"""
    Aggregate `source_graph` into an optinode within new graph. Return new node and mapping.
"""
function _copy_graph_elements_to!(new_graph::OptiGraph, source_graph::OptiGraph)
    new_node = add_node(new_graph)
    ref_map = GraphReferenceMap()

    for node in all_nodes(source_graph)
        _copy_node_to!(new_node, node, ref_map)
    end

    for edge in all_edges(source_graph)
        _copy_edge_to!(new_node, edge, ref_map)
    end

    return new_node, ref_map
end

"""
    Aggregate an optinode `source_node` into new optinode `new_node`.
"""
function _copy_node_to!(
    new_node::OptiNode, 
    source_node::OptiNode, 
    ref_map::GraphReferenceMap
)
    src = graph_backend(source_node)
    dest = graph_backend(new_node)
    index_map = MOIU.IndexMap()

    # create new variable references
    source_variables = all_variables(source_node)
    new_vars = NodeVariableRef[]
    for vref in source_variables
        new_variable_index = next_variable_index(new_node)
        new_vref = NodeVariableRef(new_node, new_variable_index)
        _add_variable_to_backend(dest, new_vref)
        index_map[graph_index(vref)] = graph_index(new_vref)
        ref_map[vref] = new_vref
    end

    # pass variable attributes
    vis_src = graph_index.(source_variables)
    MOIU.pass_attributes(dest.moi_backend, src.moi_backend, index_map, vis_src)

    # copy constraints
    constraint_types = MOI.get(source_node, MOI.ListOfConstraintTypesPresent())
    _copy_element_constraints(
        dest,
        source_node,
        index_map,
        constraint_types
    )

    # update aggregation map
    for (source_index, dest_index) in index_map.con_map
        source_cref = src.graph_to_element_map.con_map[source_index]
        dest_cref = dest.graph_to_element_map.con_map[dest_index]
        ref_map[source_cref] = dest_cref
    end
end

"""
    Aggregate an optiedge `source_edge` into new optinode `new_node`.
"""
function _copy_edge_to!(
    new_node::OptiNode, 
    source_edge::OptiEdge,
    ref_map::GraphReferenceMap
)
    _copy_edge_to!(source_graph(new_node), source_edge, ref_map) 
end

"""
    Copy an optinode to a new optigraph
"""
function _copy_node_to!(new_graph::OptiGraph, source_node::OptiNode)
    ref_map = GraphReferenceMap()
    new_node = add_node(new_graph)
    _add_to_aggregate_node!(new_node, source_node)
    return new_node, ref_map
end

"""
    Aggregate an optiedge `source_edge` into new optinode `new_node`.
"""
function _copy_edge_to!(
    graph::OptiGraph, 
    source_edge::OptiEdge,
    ref_map::GraphReferenceMap
)
    src = graph_backend(source_edge)
    dest = graph_backend(graph)
    index_map = MOIU.IndexMap()

    # populate edge index_map
    index_map = MOIU.IndexMap()
    vars = all_variables(source_edge)
    for var in vars
        source_index = src.element_to_graph_map[var]
        dest_index = dest.element_to_graph_map.var_map[ref_map[var]]
        index_map[source_index] = dest_index
    end

    # copy constraints
    constraint_types = MOI.get(source_edge, MOI.ListOfConstraintTypesPresent())
    _copy_element_constraints(
        dest,
        source_edge,
        index_map,
        constraint_types
    )

    # update ref_map constraints
    for (source_index, dest_index) in index_map.con_map
        source_cref = src.graph_to_element_map.con_map[source_index]
        dest_cref = dest.graph_to_element_map.con_map[dest_index]
        ref_map[source_cref] = dest_cref
    end

    return 
end

function aggregate_to_depth(graph::OptiGraph, max_depth::Int64=0)
    root_optigraph = OptiGraph()
    ref_map = GraphReferenceMap()
    subgraph_dict = Dict(graph => root_optigraph)

    # setup new subgraph structure
    # iterate through subgraphs until we reach the `max_depth`.
    # the last depth contains the leaf subgraphs that get converted to optinodes
    depth = 0
    last_parents = [graph] # the lowest level subgraphs that will contain nodes
    all_parents = [graph]  # all graphs that need to be copied over
    while depth < max_depth
        # the next set of subgraphs to setup an equivalent structure
        subgraphs_to_check = []
        for parent in last_parents
            new_parent = subgraph_dict[parent]
            subgraphs = get_subgraphs(parent)
            for subgraph in subgraphs
                new_subgraph = OptiGraph()
                add_subgraph!(new_parent, new_subgraph)
                subgraph_dict[subgraph] = new_subgraph
            end
            append!(subgraphs_to_check, subgraphs)
        end
        depth += 1

        # the last set of parents that will contain aggregated nodes
        last_parents = subgraphs_to_check
        append!(all_parents, last_parents)
    end

    # aggregate subgraphs into nodes at bottom leaves
    all_ref_maps = []
    for parent in last_parents
        new_parent = subgraph_dict[parent]
        leaf_subgraphs = get_subgraphs(parent)

        # aggregate the subgraphs into nodes within `new_parent`
        nodes, subgraph_ref_maps = _aggregate_subgraphs!(new_parent, parent)
        append!(all_ref_maps, subgraph_ref_maps)
    end

    # merge aggregation maps
    for sub_ref_map in all_ref_maps
        merge!(ref_map, sub_ref_map)
    end

    #now copy nodes and edges going back up the tree
    for graph in reverse(all_parents)
        nodes = local_nodes(graph)
        edges = local_edges(graph)
        new_graph = subgraph_dict[graph]

        # copy optinodes
        for node in nodes
            new_node, ref_map = _copy_node_to!(new_graph, node)
            merge!(ref_map, ref_map)
        end

        # copy optiedges
        for edge in edges
            _copy_edge_to!(new_graph, edge, ref_map)
        end
    end

    _copy_attributes_to!(root_optigraph, graph, ref_map)

    return root_optigraph, ref_map

end

"""
    Aggregate the subgraphs within `source_graph` into nodes withing `new_subgraph`.
"""
function _aggregate_subgraphs!(new_graph::OptiGraph, source_graph::OptiGraph)
    # aggregate each subgraph into a node in new_graph
    nodes, ref_maps = [], []
    for subgraph in get_subgraphs(source_graph)
        node, ref_map = _copy_graph_elements_to!(new_graph, subgraph)
        push!(nodes, node)
        push!(ref_maps, ref_map)
    end
    return nodes, ref_maps
end

"""
    aggregate!(graph::OptiGraph, max_depth::Int64)

Aggregate `graph` by converting subgraphs into optinodes. The `max_depth` determines how many levels of
subgraphs remain in the new aggregated optigraph. For example, a `max_depth` of `0` signifies there should be no subgraphs in
the aggregated optigraph.
"""
function aggregate_to_depth!(graph::OptiGraph, max_depth::Int64=0)
    temp_graph, ref_map = aggregate_to_depth(graph, max_depth)
    Base.empty!(graph)

    # set fields
    graph.backend = temp_graph.backend
    graph.backend.optigraph = graph
    graph.obj_dict = new_graph.obj_dict
    graph.ext = new_graph.ext
    graph.optinodes = new_graph.optinodes
    graph.optiedges = new_graph.optiedges
    graph.subgraphs = new_graph.subgraphs
    graph.optiedge_map = new_graph.optiedge_map
    graph.node_to_graphs = new_graph.node_to_graphs
    return graph
end
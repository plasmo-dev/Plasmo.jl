"""
    GraphReferenceMap

Mapping between variable and constraint reference of a OptiGraph to an Combined Model.
The reference of the combined model can be obtained by indexing the map with the 
reference of the corresponding original optinode.
"""
struct GraphReferenceMap
    # map variables and from original optigraph to new aggregate node or graph
    var_map::OrderedDict{NodeVariableRef,NodeVariableRef}
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
        OrderedDict{NodeVariableRef,NodeVariableRef}(),
        OrderedDict{JuMP.ConstraintRef,JuMP.ConstraintRef}(),
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
function aggregate(graph::OptiGraph; name=gensym())
    # aggregate into a graph containing a single optinode
    new_graph = OptiGraph(; name=name)
    new_node, ref_map = _copy_graph_elements_to!(new_graph, graph)
    # copy other model attributes (such as the objective function)
    # setup index_map from the ref_map
    _copy_attributes_to!(new_graph, graph, ref_map)

    # copy objective function to node
    JuMP.set_objective(new_node, objective_sense(new_graph), objective_function(new_graph))
    return new_node, ref_map
end

"""
    Aggregate `source_graph` into an optinode within new graph. Return new node and mapping.
"""
function _copy_graph_elements_to!(new_graph::OptiGraph, source_graph::OptiGraph)
    new_node = add_node(
        new_graph;
        label=Symbol(new_graph.label, Symbol(".n"), length(new_graph.optinodes) + 1),
    )
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
    Copy graph attributes from `source_graph` to the new optigraph `new_graph`.

These attributes include all model and optimizer attributes
"""
function _copy_attributes_to!(
    new_graph::OptiGraph, source_graph::OptiGraph, ref_map::GraphReferenceMap
)
    src = graph_backend(source_graph)
    dest = graph_backend(new_graph)
    index_map = MOIU.IndexMap()

    # NOTE: we use an if statement because the source graph does not necessarily have all 
    # the variables or constraints. we just want to pass the attributes that would be 
    # exposed such as the graph objective function.
    for (source_vref, dest_vref) in ref_map.var_map
        # TODO: use outer method here; don't access data members directly 
        if source_vref in keys(src.element_to_graph_map.var_map)
            index_map[graph_index(source_graph, source_vref)] = graph_index(dest_vref)
        end
    end
    for (source_cref, dest_cref) in ref_map.con_map
        if source_cref in keys(src.element_to_graph_map.con_map)
            index_map[graph_index(source_graph, source_cref)] = graph_index(dest_cref)
        end
    end
    # TODO: avoid using direct reference to moi_backend
    MOIU.pass_attributes(dest.moi_backend, src.moi_backend, index_map)
    return nothing
end

"""
    Copy (append) the `source_node` backend model into `new_node`.
"""
function _copy_node_to!(
    new_node::OptiNode, source_node::OptiNode, ref_map::GraphReferenceMap
)
    src = graph_backend(source_node)
    dest = graph_backend(new_node)
    index_map = MOIU.IndexMap()

    _copy_variables!(new_node, source_node, ref_map, index_map)

    return _copy_constraints!(new_node, source_node, ref_map, index_map)
end

"""
    Copy an optinode to a new optigraph.
"""
function _copy_node_to!(new_graph::OptiGraph, source_node::OptiNode)
    ref_map = GraphReferenceMap()
    new_node = add_node(new_graph)
    _copy_node_to!(new_node, source_node, ref_map)
    return new_node, ref_map
end

function _copy_variables!(
    new_node::OptiNode,
    source_node::OptiNode,
    ref_map::GraphReferenceMap,
    index_map::MOIU.IndexMap,
)
    # get relevant backends
    src = graph_backend(source_node)
    dest = graph_backend(new_node)

    # create new variables
    source_variables = all_variables(source_node)
    for nvref in source_variables
        new_variable_index = next_variable_index(new_node)
        new_vref = NodeVariableRef(new_node, new_variable_index)
        MOI.add_variable(dest, new_vref)
        index_map[graph_index(nvref)] = graph_index(new_vref)
        ref_map[nvref] = new_vref
    end

    # pass variable attributes
    vis_src = graph_index.(source_variables)
    MOIU.pass_attributes(dest.moi_backend, src.moi_backend, index_map, vis_src)

    # set new variable names
    for nvref in all_variables(source_node)
        new_variable = ref_map[nvref]
        JuMP.set_name(new_variable, "$(new_node.label)" * "." * JuMP.name(nvref))
    end
end

"""
    Copy the constraints from a node or edge into a new node.
"""
function _copy_constraints!(
    new_node::OptiNode,
    source_element::OptiElement,
    ref_map::GraphReferenceMap,
    index_map::MOIU.IndexMap,
)
    # get relevant backends
    src = graph_backend(source_element)
    dest = graph_backend(new_node)

    # copy each constraint by iterating through each type
    constraint_types = MOI.get(src.moi_backend, MOI.ListOfConstraintTypesPresent())
    for (F, S) in constraint_types
        cis_src = MOI.get(source_element, MOI.ListOfConstraintIndices{F,S}())
        index_map_FS = index_map[F, S]
        for ci in cis_src
            # TODO: use references to elements instead so we don't have to hardcode backend
            src_func = MOI.get(src.moi_backend, MOI.ConstraintFunction(), ci)
            src_set = MOI.get(src.moi_backend, MOI.ConstraintSet(), ci)
            # src_func = MOI.get(source_element, MOI.ConstraintFunction(), ci)
            # src_set = MOI.get(source_element, MOI.ConstraintSet(), ci)

            # get source cref to lookup constraint shape
            src_cref = JuMP.constraint_ref_with_index(src, ci)
            new_shape = src_cref.shape

            # create a new ConstraintRef
            new_constraint_index = next_constraint_index(
                new_node, typeof(src_func), typeof(src_set)
            )::MOI.ConstraintIndex{typeof(src_func),typeof(src_set)}
            new_cref = ConstraintRef(new_node, new_constraint_index, new_shape)

            # create new MOI function
            new_func = MOIU.map_indices(index_map, src_func)
            dest_index = MOI.add_constraint(dest, new_cref, new_func, src_set)

            # update index_map and ref_map
            index_map_FS[ci] = dest_index
            ref_map[src_cref] = new_cref
        end
        # pass constraint attributes
        MOIU.pass_attributes(dest.moi_backend, src.moi_backend, index_map_FS, cis_src)
    end
end

"""
    Aggregate an optiedge `source_edge` into new optinode `new_node`.
"""
function _copy_edge_to!(
    new_node::OptiNode, source_edge::OptiEdge, ref_map::GraphReferenceMap
)
    src = graph_backend(source_edge)
    dest = graph_backend(new_node)

    # setup variable index map
    index_map = MOIU.IndexMap()
    vars = all_variables(source_edge)
    for var in vars
        source_index = graph_index(src, var)
        dest_index = graph_index(dest, ref_map[var])
        index_map[source_index] = dest_index
    end

    # copy constraints
    _copy_constraints!(new_node, source_edge, ref_map, index_map)
    return nothing
end

# TODO
"""
    Aggregate an optiedge `source_edge` into new optinode `new_node`.
"""
function _copy_edge_to!(
    new_graph::OptiGraph, source_edge::OptiEdge, ref_map::GraphReferenceMap
)
    # create a new edge

    # copy constraints from source_edge
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
            new_node, node_ref_map = _copy_node_to!(new_graph, node)
            merge!(ref_map, node_ref_map)
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

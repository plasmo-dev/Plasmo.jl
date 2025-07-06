# Enable printing the graph
function Base.string(rgraph::RemoteOptiGraph)
    return "RemoteOptiGraph"
end
Base.print(io::IO, graph::RemoteOptiGraph) = Base.print(io, Base.string(graph))
Base.show(io::IO, graph::RemoteOptiGraph) = Base.print(io, graph)

function source_graph(rgraph::RemoteOptiGraph) return rgraph.parent_graph end

# If we directly create the remote reference on the remote worker, there are issues
# with equality of the resulting remoterefs. For instance, a node's remote graph
# may not be equal to the remotegraph from which it was created. Consequently, we have
# this kind of hacky interface for turning whatever object is returned into the
# appropriate object

function _return_remotegraph_object(rgraph::RemoteOptiGraph, obj::Plasmo.OptiNode)
    return (obj.idx, obj.label)
end

function _return_remotegraph_object(rgraph::RemoteOptiGraph, obj::Plasmo.EdgeConstraintRef)
    edge = JuMP.owner_model(obj)
    lnodes = edge.nodes
    elabel = edge.label
    cref_index = obj.index
    cref_shape = obj.shape

    node_data = [(node.idx, node.label) for node in lnodes]
    #(node_list; should be )
    return (node_data, elabel, cref_index, cref_shape)
end

function _return_remotegraph_object(rgraph::RemoteOptiGraph, obj)
    error("Retrieving object resulted in an object of type $(typeof(obj)) which is not yet supported")
end

function _build_fetched_object_from_data(rgraph::RemoteOptiGraph, data::Tuple{Plasmo.NodeIndex, Base.RefValue{Symbol}})
    return RemoteNodeRef(rgraph, data[1], data[2])
end

function _build_fetched_object_from_data(rgraph::RemoteOptiGraph, data::Tuple{Vector{Tuple}, Symbol, FT, ST}) where {FT <: MOI.AbstractFunction, ST <: JuMP.AbstractShape}
    rnodes = [RemoteNodeRef(rgraph, t[1], t[2]) for t in data[1]]
    redge = RemoteEdgeRef(rgraph, rnodes, data[2])
    return ConstraintRef(redge, data[3], data[4])
end


#TODO: Support arrays of these objects
#TODO: Support adding named expressions to the graph; currently only do link constraints

function Base.getindex(rgraph::RemoteOptiGraph, sym::Symbol)
    if haskey(rgraph.obj_dict, sym)
        return rgraph.obj_dict[sym]
    else
        f = @spawnat rgraph.worker begin
            lg = local_graph(rgraph)
            if haskey(lg.obj_dict, sym)
                obj = lg.obj_dict[sym]
            else
                error("No object with name $sym is registered on given OptiGraph")
            end
            _return_remotegraph_object(rgraph, obj)
            # return data to then build these separately
        end
        return _build_fetched_object_from_data(rgraph, fetch(f))
    end
end

# (local_node.idx, local_node.label)
#     end
#     node_tuple = fetch(f)

#     return RemoteNodeRef(rgraph, node_tuple[1], node_tuple[2])

###### Functions for getting the remote data from a RemoteOptiGraph ######
function local_graph(rgraph::RemoteOptiGraph)
    return localpart(rgraph.graph)[1]
end

function print_local_graph(rgraph::RemoteOptiGraph)
    @spawnat rgraph.worker println(localpart(rgraph.graph)[1])
    return nothing
end

function get_local_graph(rgraph::RemoteOptiGraph)
    f = @spawnat rgraph.worker localpart(rgraph.graph)[1]
    return fetch(f)
end

"""
    Plasmo.add_subgraph(rgraph::RemoteOptigraph; worker::Int=1)

Add a RemoteOptiGraph as a subgraph to `rgraph`. This instantiates a new RemoteOptiGraph
that contains a remote graph on worker `worker`
"""
function add_subgraph(rgraph::RemoteOptiGraph; worker::Int=1)
    new_rgraph = RemoteOptiGraph(worker=worker)
    push!(rgraph.subgraphs, new_rgraph)
    new_rgraph.parent_graph = rgraph
    return new_rgraph
end

"""
    add_subgraph(rgraph::RemoteOptiGraph, rsubgraph::RemoteOptiGraph)

Add `rsubgraph` as a subgraph to `rgraph`
"""
function add_subgraph(rgraph::RemoteOptiGraph, rsubgraph::RemoteOptiGraph)
    subgraphs = rgraph.subgraphs
    if rsubgraph in subgraphs
        println("$rsubgraph is already a subgraph of $rgraph")
    else
        push!(subgraphs, rsubgraph)
        rsubgraph.parent_graph = rgraph
    end
    return nothing
end 

"""
    Plasmo.all_nodes(rgraph::RemoteOptiGraph)

Returns a vector of RemoteNodeRefs for all nodes stored on remote OptiGraphs on 
`rgraph` and all of its subgraphs
"""
function all_nodes(rgraph::RemoteOptiGraph)
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        nodes = Plasmo.all_nodes(lg)
        [(node.idx, node.label) for node in nodes]
        #[_convert_local_to_remote(rgraph, node) for node in nodes] #TODO: Move the local_var_to_remote outside @spawnat? Not sure if this is being called in the right place. May need to rethink this
    end
    node_tuples = fetch(f)
    nodes = [RemoteNodeRef(rgraph, idx, label) for (idx, label) in node_tuples]
    for g in rgraph.subgraphs
        append!(nodes, all_nodes(g))
    end
    return nodes
end

"""
    Plasmo.local_nodes(rgraph::RemoteOptiGraph)

Returns a vector of RemoteNodeRefs for all nodes stored on `rgraph`'s remote OptiGraph. 
This returns all nodes on remote OptiGraph, but none of the nodes on the sub-RemoteOptiGraphs. 

NOTE: the remote OptiGraph stored on `rgraph` may contain multiple sub-opitgraphs, and this 
function still returns all nodes contained on these "local" subgraphs.
"""
function local_nodes(rgraph::RemoteOptiGraph)
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        nodes = Plasmo.all_nodes(lg)
        [(node.idx, node.label) for node in nodes]
        #[_convert_local_to_remote(rgraph, node) for node in nodes] #TODO: Move the local_var_to_remote outside @spawnat? Not sure if this is being called in the right place. May need to rethink this
    end
    node_tuples = fetch(f)
    nodes = [RemoteNodeRef(rgraph, idx, label) for (idx, label) in node_tuples]
    return nodes
end

"""
    Plasmo.all_subgraphs(rgraph::RemoteOptiGraph)

Returns a vector of all sub-RemoteOptiGraphs contained in `rgraph` and all 
sub-RemoteOptiGraphs nested within any of these sub-RemoteOptiGraphs.
"""
function all_subgraphs(rgraph::RemoteOptiGraph)
    subs = collect(rgraph.subgraphs)
    for subgraph in rgraph.subgraphs
        subs = [subs; all_subgraphs(subgraph)]
    end
    return subs
end

"""
    Plasmo.local_subgraphs(rgraph::RemoteOptiGraph)

Returns the vector of sub-RemoteOptiGraphs stored directly on `rgraph`
Does not include subgraphs nested in subgraphs
"""
function local_subgraphs(rgraph::RemoteOptiGraph)
    return rgraph.subgraphs
end

"""
    Plasmo.num_local_subgraphs(rgraph::RemoteOptiGraph)

Returns the number of sub-RemoteOptiGraphs stored directly on `rgraph`
Does not include subgraphs nested in subgraphs
"""
function num_local_subgraphs(rgraph::RemoteOptiGraph)
    return length(rgraph.subgraphs) 
end

"""
    Plasmo.num_subgraphs(rgraph)

Returns the number of all sub-RemoteOptiGraphs contained in `rgraph`, including
subgraphs of subgraphs
"""
function num_subgraphs(rgraph::RemoteOptiGraph)
    n_subs = num_local_subgraphs(rgraph)
    for subgraph in rgraph.subgraphs
        n_subs += num_subgraphs(subgraph)
    end
end

"""
    Plasmo.containing_optigraphs(robj::RemoteOptiObject)

returns all the RemoteOptiGraphs that contain the RemoteOptiObject
"""
function containing_optigraphs(robj::RemoteOptiObject)
    sg = source_graph(robj)
    if isnothing(sg.parent_graph)
        return [sg]
    else
        return [sg; containing_optigraphs(sg)]
    end    
end

"""
    JuMP.add_constraint(rgraph::RemoteOptiGraph, con::JuMP.AbstractConstraint, name::String="")

Add a new constraint to `rgraph` (which will be placed on `rgraph`'s remote OptiGraph if 
applicable). This method is called internally when a user uses the JuMP.@constraint macro.
"""
function JuMP.add_constraint(
    rgraph::RemoteOptiGraph, con::JuMP.AbstractConstraint, name::String=""
)
    rnodes = collect_nodes(JuMP.jump_function(con))
    @assert length(rnodes) > 0
    length(rnodes) > 1 || error("Cannot create a linking constraint on a single node")

    if all(n -> n.remote_graph == rgraph, rnodes)
        rcref = _build_constraint_ref(rgraph, con, name=name)
    else
        redge = add_edge(rgraph, rnodes...)
        con = JuMP.model_convert(redge, con)
        rcref = _build_constraint_ref(redge, con)
    end
    return rcref
end 

# build the constraint reference
function _build_constraint_ref(rgraph::RemoteOptiGraph, con::JuMP.AbstractConstraint; name::String="")
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        new_expr = _convert_remote_to_local(rgraph, con.func)
        lcon = JuMP.ScalarConstraint(new_expr, con.set)
        cref = JuMP.add_constraint(lg, lcon, name)
        ledge = JuMP.owner_model(cref)
        lnodes = ledge.nodes
        node_tuples = [(node.idx, node.label) for node in lnodes]
        (cref.index, cref.shape, node_tuples, ledge.label)
    end
    cref_data = fetch(f)
    rnodes = OrderedSet([RemoteNodeRef(rgraph, idx, label) for (idx, label) in cref_data[3]])
    redge = RemoteEdgeRef(rgraph, rnodes, cref_data[4])
    return ConstraintRef(redge, cref_data[1], cref_data[2])
end

###### Support optimization interface for graphs ######

function JuMP.optimize!(rgraph::RemoteOptiGraph)#TODO: Figure out how to support kwargs for this
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        JuMP.optimize!(lg)
    end
    return fetch(f)
end

function JuMP.set_optimizer(rgraph::RemoteOptiGraph, optimizer)
    remotecall_wait(rgraph.worker) do
        lg = local_graph(rgraph)    
        JuMP.set_optimizer(lg, optimizer)
    end
    return nothing
end

function JuMP.set_optimizer_attribute(rgraph::RemoteOptiGraph, pairs::Pair...)
    remotecall_wait(rgraph.worker) do
        lg = local_graph(rgraph)
        JuMP.set_optimizer_attribute(lg, pairs...)
    end
    return nothing
end #TODO: go through and decide if all my functions should be using `remotecall_wait` or `@spawnat`

function JuMP.set_objective(
    rgraph::RemoteOptiGraph, sense::MOI.OptimizationSense, func::JuMP.AbstractJuMPScalar
)
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        new_func = _convert_remote_to_local(rgraph, func)
        JuMP.set_objective(lg, sense, new_func)
    end
    return func
end

function JuMP.set_objective_function(
    rgraph::RemoteOptiGraph, func::JuMP.AbstractJuMPScalar
)
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        new_func = _convert_remote_to_local(rgraph, func)
        JuMP.set_objective_function(lg, new_func)
    end
    return func
end

function JuMP.set_objective_sense(
    rgraph::RemoteOptiGraph, sense::MOI.OptimizationSense
)
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        JuMP.set_objective_sense(lg, sense)
    end
    return nothing
end

function set_to_node_objectives(rgraph::RemoteOptiGraph)
    @spawnat rgraph.worker set_to_node_objectives(local_graph(rgraph))
    return nothing
end

function JuMP.objective_value(rgraph::RemoteOptiGraph)
    f = @spawnat rgraph.worker JuMP.objective_value(local_graph(rgraph))
    return fetch(f)
end

function JuMP.objective_function(rgraph::RemoteOptiGraph)
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        lobj_func = JuMP.objective_function(lg)
        robj_func = _convert_local_to_remote(rgraph, lobj_func)
        robj_func
    end # TODO: Make sure the references are correct here
    return fetch(f)
end

function JuMP.termination_status(rgraph::RemoteOptiGraph)
    f = @spawnat rgraph.worker begin
        lgraph = local_graph(rgraph)
        JuMP.termination_status(lgraph)
    end
    return fetch(f)
end

function JuMP.object_dictionary(rgraph::RemoteOptiGraph)
    return rgraph.obj_dict
end
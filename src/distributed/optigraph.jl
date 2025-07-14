# Enable printing the graph
function Base.string(rgraph::RemoteOptiGraph)
    return "RemoteOptiGraph"
end
Base.print(io::IO, graph::RemoteOptiGraph) = Base.print(io, Base.string(graph))
Base.show(io::IO, graph::RemoteOptiGraph) = Base.print(io, graph)

function source_graph(rgraph::RemoteOptiGraph) return rgraph.parent_graph end


function Base.getindex(rgraph::RemoteOptiGraph, sym::Symbol)
    if haskey(rgraph.obj_dict, sym)
        return rgraph.obj_dict[sym]
    else
        darray = rgraph.graph

        f = @spawnat rgraph.worker begin
            lgraph = localpart(darray)[1]
            if haskey(lgraph.obj_dict, sym)
                obj = lgraph.obj_dict[sym]
            else
                error("No object with name $sym is registered on given OptiGraph")
            end
            #TODO: Support arrays of these objects; I think the _convert function only handles single objects, not arrays of objects
            _convert_local_to_proxy(lgraph, obj)
            # return data to then build these separately
        end
        pobj = fetch(f)
        return _convert_proxy_to_remote(rgraph, pobj)
    end
end

###### Functions for getting the remote data from a RemoteOptiGraph ######
function local_graph(rgraph::RemoteOptiGraph)
    return localpart(rgraph.graph)[1]
end

function local_graph(darray::DistributedArrays.DArray)
    return localpart(darray)[1]
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
    darray = rgraph.graph

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        nodes = Plasmo.all_nodes(lgraph)
        [_convert_local_to_proxy(lgraph, node) for node in nodes]
    end
    pnodes = fetch(f)
    nodes = [_convert_proxy_to_remote(rgraph, node) for node in pnodes]
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
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        nodes = Plasmo.all_nodes(lgraph)
        [_convert_local_to_proxy(lgraph, node) for node in nodes]
    end
    pnodes = fetch(f)
    nodes = [_convert_proxy_to_remote(rgraph, node) for node in pnodes]
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
    darray = rgraph.graph
    pexpr = _convert_remote_to_proxy(rgraph, con.func)
    con_set = con.set

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        new_expr = _convert_proxy_to_local(lgraph, pexpr)
        lcon = JuMP.ScalarConstraint(new_expr, con_set)
        cref = JuMP.add_constraint(lgraph, lcon, name)
        pcref = _convert_local_to_proxy(lgraph, cref)
        pcref
    end
    pcref = fetch(f)
    return _convert_proxy_to_remote(rgraph, pcref)
end

###### Support optimization interface for graphs ######

function JuMP.optimize!(rgraph::RemoteOptiGraph)#TODO: Figure out how to support kwargs for this
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        JuMP.optimize!(lgraph)
    end
    return nothing
end

function JuMP.set_optimizer(rgraph::RemoteOptiGraph, optimizer)
    darray = rgraph.graph
    remotecall_wait(rgraph.worker) do
        lgraph = localpart(darray)[1]
        JuMP.set_optimizer(lgraph, optimizer)
    end
    return nothing
end

function JuMP.set_optimizer_attribute(rgraph::RemoteOptiGraph, pairs::Pair...)
    darray = rgraph.graph
    remotecall_wait(rgraph.worker) do
        lgraph = localpart(darray)[1]
        JuMP.set_optimizer_attribute(lgraph, pairs...)
    end
    return nothing
end #TODO: go through and decide if all my functions should be using `remotecall_wait` or `@spawnat`

function JuMP.set_objective(
    rgraph::RemoteOptiGraph, sense::MOI.OptimizationSense, func::JuMP.AbstractJuMPScalar
)
    darray = rgraph.graph
    pfunc = _convert_remote_to_proxy(rgraph, func)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        new_func = _convert_proxy_to_local(lgraph, pfunc)
        JuMP.set_objective(lgraph, sense, new_func)
    end
    return func
end

function JuMP.set_objective_function(
    rgraph::RemoteOptiGraph, func::JuMP.AbstractJuMPScalar
)
    darray = rgraph.graph
    pfunc = _convert_remote_to_proxy(rgraph, func)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        new_func = _convert_proxy_to_local(lgraph, pfunc)
        JuMP.set_objective_function(lgraph, new_func)
    end
    return func
end

function JuMP.set_objective_sense(
    rgraph::RemoteOptiGraph, sense::MOI.OptimizationSense
)
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        JuMP.set_objective_sense(lgraph, sense)
    end
    return nothing
end

function set_to_node_objectives(rgraph::RemoteOptiGraph)
    darray = rgraph.graph
    @spawnat rgraph.worker set_to_node_objectives(localpart(darray)[1])
    return nothing
end

function JuMP.objective_value(rgraph::RemoteOptiGraph)
    darray = rgraph.graph
    f = @spawnat rgraph.worker JuMP.objective_value(localpart(darray)[1])
    return fetch(f)
end

function JuMP.dual_objective_value(rgraph::RemoteOptiGraph)
    darray = rgraph.graph
    f = @spawnat rgraph.worker JuMP.dual_objective_value(localpart(darray)[1])
    return fetch(f)
end

function JuMP.objective_function(rgraph::RemoteOptiGraph)
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lobj_func = JuMP.objective_function(lgraph)
        robj_func = _convert_local_to_proxy(lgraph, lobj_func)
        robj_func
    end # TODO: Make sure the references are correct here
    pobj_func = fetch(f)
    return _convert_proxy_to_remote(rgraph, pobj_func)
end

function JuMP.termination_status(rgraph::RemoteOptiGraph)
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        JuMP.termination_status(lgraph)
    end
    return fetch(f)
end

function JuMP.object_dictionary(rgraph::RemoteOptiGraph)
    return rgraph.obj_dict
end
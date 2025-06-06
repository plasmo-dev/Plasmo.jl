function Base.string(rgraph::RemoteOptiGraph)
    return "RemoteOptiGraph"
end
Base.print(io::IO, graph::RemoteOptiGraph) = Base.print(io, Base.string(graph))
Base.show(io::IO, graph::RemoteOptiGraph) = Base.print(io, graph)

function source_graph(rgraph::RemoteOptiGraph) return rgraph.parent_graph end

#TODO: Figure out displaying c  onstraints
function Base.getindex(rgraph::RemoteOptiGraph, sym::Symbol)
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        #new_sym = Symbol(rgraph.label, ".", sym)
        local_node = Plasmo.get_node(lg, sym)
        (local_node.idx, local_node.label.x)
    end
    node_tuple = fetch(f)

    return RemoteNodeRef(rgraph, node_tuple[1], node_tuple[2])
end
#TODO: Each call will create a new RemoteNodeRef; need to figure out how to not duplicate these; maybe we have a dictionary of node symbols to node refs in the RemoteOptiGraph? 
# Need to double check this. If I try to set two of the above functions equal to each other for different calls of the same node (even using ===), it says it is true; looking online,it looks like this might result in different allocations in memory but you cannot tell on the Julia language level

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

function add_subgraph(rgraph::RemoteOptiGraph; worker::Int=1)
    new_rgraph = RemoteOptiGraph(worker=worker)
    push!(rgraph.subgraphs, new_rgraph)
    new_rgraph.parent_graph = rgraph
    return new_rgraph
end

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

function all_nodes(rgraph::RemoteOptiGraph)
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        nodes = Plasmo.all_nodes(lg)
        [(node.idx, node.label.x) for node in nodes]
        #[local_node_to_remote(rgraph, node) for node in nodes] #TODO: Move the local_var_to_remote outside @spawnat? Not sure if this is being called in the right place. May need to rethink this
    end
    node_tuples = fetch(f)
    nodes = [RemoteNodeRef(rgraph, idx, label) for (idx, label) in node_tuples]
    for g in rgraph.subgraphs
        append!(nodes, all_nodes(g))
    end
    return nodes
end

function all_subgraphs(rgraph::RemoteOptiGraph)
    subs = collect(rgraph.subgraphs)
    for subgraph in rgraph.subgraphs
        subs = [subs; all_subgraphs(subgraph)]
    end
    return subs
end

function local_subgraphs(rgraph::RemoteOptiGraph)
    return rgraph.subgraphs
end

function num_local_subgraphs(rgraph::RemoteOptiGraph)
    return length(rgraph.subgraphs) 
end

function num_subgraphs(rgraph::RemoteOptiGraph)
    n_subs = num_local_subgraphs(rgraph)
    for subgraph in rgraph.subgraphs
        n_subs += num_subgraphs(subgraph)
    end
end

function containing_optigraphs(robj::RemoteOptiObject)
    sg = source_graph(robj)
    if isnothing(sg.parent_graph)
        return [sg]
    else
        return [sg; containing_optigraphs(sg)]
    end    
end
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

function _build_constraint_ref(rgraph::RemoteOptiGraph, con::JuMP.AbstractConstraint; name::String="")
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        new_expr = _convert_remote_to_local(rgraph, con.func)
        lcon = JuMP.ScalarConstraint(new_expr, con.set)
        cref = JuMP.add_constraint(lg, lcon, name)
        ledge = JuMP.owner_model(cref)
        lnodes = ledge.nodes
        node_tuples = [(node.idx, node.label.x) for node in lnodes]
        #redge = local_edge_to_remote(rgraph, ledge)
        #rcref = ConstraintRef(redge, cref.index, cref.shape)
        #rcref
        (cref.index, cref.shape, node_tuples, ledge.label)
    end
    cref_data = fetch(f)
    rnodes = OrderedSet([RemoteNodeRef(rgraph, idx, label) for (idx, label) in cref_data[3]])
    redge = RemoteEdgeRef(rgraph, rnodes, cref_data[4])
    return ConstraintRef(redge, cref_data[1], cref_data[2])
end

function _build_constraint_ref(redge::RemoteOptiEdge, con::JuMP.AbstractConstraint)
    # get moi function and set
    moi_func = JuMP.moi_function(con)
    moi_set = JuMP.moi_set(con)

    # create constraint index and reference
    constraint_index = next_constraint_index(
        redge, typeof(moi_func), typeof(moi_set)
    )::MOI.ConstraintIndex{typeof(moi_func),typeof(moi_set)}
    cref = ConstraintRef(redge, constraint_index, JuMP.shape(con))

    redge.constraint_refs[constraint_index] = cref
    redge.constraints[cref] = con

    return cref
end

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


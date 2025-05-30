################################### Graph Interface #######################################
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
        [node_to_remote_ref(rgraph, node) for node in nodes] #TODO: Move the var_to_remote_ref outside @spawnat? Not sure if this is being called in the right place. May need to rethink this
    end
    nodes = fetch(f)
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

function JuMP.all_variables(rgraph::RemoteOptiGraph)
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        all_vars = JuMP.all_variables(lg)
        [var_to_remote_ref(rgraph, var) for var in all_vars] #TODO: Move the var_to_remote_ref outside @spawnat? Not sure if this is being called in the right place. May need to rethink this
    end
    
    return fetch(f)
end


################################### Optimizer and Objective #######################################


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
    return nothing
end

function JuMP.set_objective(
    rnode::RemoteNodeRef, sense::MOI.OptimizationSense, func::JuMP.AbstractJuMPScalar
)
    rgraph = rnode.remote_graph
    f = @spawnat rgraph.worker begin
        new_func = _convert_remote_to_local(rnode, func)
        lnode = get_node(rgraph, rnode)
        JuMP.set_objective(lnode, sense, new_func)
    end
    return nothing
end

function JuMP.set_objective_function(
    rgraph::RemoteOptiGraph, func::JuMP.AbstractJuMPScalar
)
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        new_func = _convert_remote_to_local(rgraph, func)
        JuMP.set_objective_function(lg, new_func)
    end
    return nothing
end

function JuMP.set_objective_function(
    rnode::RemoteNodeRef, func::JuMP.AbstractJuMPScalar
)
    rgraph = rnode.remote
    f = @spawnat rgraph.worker begin
        new_func = _convert_remote_to_local(rnode, func)
        lnode = get_node(rgraph, rnode)
        JuMP.set_objective_function(lnode, new_func)
    end
    return nothing
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

function JuMP.set_objective_sense(
    rnode::RemoteNodeRef, sense::MOI.OptimizationSense
)
    rgraph = rnode.remote
    f = @spawnat rgraph.worker begin
        lnode = get_node(rgraph, rnode)
        JuMP.set_objective_sense(lnode, sense)
    end
    return nothing
end

function set_to_node_objectives(rgraph::RemoteOptiGraph)
    @spawnat rgraph.worker set_to_node_objectives(local_graph(rgraph))
    return nothing
end

#TODO: objective_function


################################### Indexing and Printing #######################################


function Base.string(rnode::RemoteNodeRef)
    return String(rnode.node_label.x)
end
Base.print(io::IO, rnode::RemoteNodeRef) = Base.print(io, Base.string(rnode))
Base.show(io::IO, rnode::RemoteNodeRef) = Base.print(io, rnode)

function Base.string(redge::RemoteEdgeRef)
    return String(redge.label)
end
Base.print(io::IO, redge::RemoteEdgeRef) = Base.print(io, Base.string(redge))
Base.show(io::IO, redge::RemoteEdgeRef) = Base.print(io, redge)

function Base.string(rgraph::RemoteOptiGraph)
    return "RemoteOptiGraph"
end
Base.print(io::IO, graph::RemoteOptiGraph) = Base.print(io, Base.string(graph))
Base.show(io::IO, graph::RemoteOptiGraph) = Base.print(io, graph)

function Base.string(rvar::RemoteVariableRef)
    return Base.string(rvar.node) * "[" * String(rvar.name) * "]"
end

Base.print(io::IO, rvar::RemoteVariableRef) = Base.print(io, Base.string(rvar))
Base.show(io::IO, rvar::RemoteVariableRef) = Base.print(io, rvar)

function Base.string(rcon::RemoteEdgeConstraintRef)
    redge = rcon.model
    rcon = redge.constraints[rcon]
    mode = JuMP.MIME("text/plain")
    return JuMP.function_string(mode, rcon) * " " * JuMP.in_set_string(mode, rcon)
end

Base.print(io::IO, rcon::RemoteEdgeConstraintRef) = Base.print(io, Base.string(rcon))
Base.show(io::IO, rcon::RemoteEdgeConstraintRef) = Base.print(io, Base.string(rcon))

function JuMP.index(rvar::RemoteVariableRef) return rvar.index end

function JuMP.owner_model(rvar::RemoteVariableRef) return rvar.node end

function JuMP.name(rvar::RemoteVariableRef) return Base.string(rvar) end

function source_graph(redge::RemoteEdgeRef) return redge.remote_graph end
function source_graph(rnode::RemoteNodeRef) return rnode.remote_graph end
function source_graph(rgraph::RemoteOptiGraph) return rgraph.parent_graph end

function JuMP.is_valid(rnode::RemoteNodeRef, rvar::RemoteVariableRef)
    if rvar.node == rnode
        return true
    else
        return false
    end
end

function Base.setindex!(rnode::RemoteNodeRef, value, name::Symbol) #TODO: Consider whether we should do this differently without an object dictionary
    return nothing
end

#TODO: Figure out displaying constraints
function Base.getindex(rgraph::RemoteOptiGraph, sym::Symbol)
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        #new_sym = Symbol(rgraph.label, ".", sym)
        local_node = Plasmo.get_node(lg, sym)
        (local_node.idx, local_node.label)
    end
    node_tuple = fetch(f)

    return RemoteNodeRef(rgraph, node_tuple[1], node_tuple[2])
end
#TODO: Each call will create a new RemoteNodeRef; need to figure out how to not duplicate these; maybe we have a dictionary of node symbols to node refs in the RemoteOptiGraph? 
# Need to double check this. If I try to set two of the above functions equal to each other for different calls of the same node (even using ===), it says it is true; looking online,it looks like this might result in different allocations in memory but you cannot tell on the Julia language level

function Base.getindex(rnode::RemoteNodeRef, sym::Symbol)
    rgraph = rnode.remote_graph
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        local_node = Plasmo.get_node(rgraph, rnode)
        var = local_node[sym]
        var.index # get this from the symbol
    end
    moi_idx = fetch(f)

    return RemoteVariableRef(rnode, moi_idx, sym)
end


################################### Internals and Macros #######################################


function get_node(graph::OptiGraph, sym::Symbol)
    for n in all_nodes(graph)
        if n.label.x == sym
            return n
        end 
    end
    error("Symbol $sym not saved on remotegraph")
end

function add_node(rgraph::RemoteOptiGraph)
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        n = add_node(lg)
        (n.idx, n.label)
    end
    node_tuple = fetch(f)
    return RemoteNodeRef(rgraph, node_tuple[1], node_tuple[2])
end

function add_node(rgraph::RemoteOptiGraph, sym::Symbol) # TODO: Rethink whether this can be merged with previous function; the problem is that I want to keep the kwarg default of add_node(graph::OptiGraph), which also calls length(graph.optinodes); trying to use that same default argument in the add_node(rgraph::RemoteOptiGraph) means having to query the subgraph and get the number of nodes; probably not a big deal, but might require an extra fetch
    f = @spawnat rgraph.worker begin
        n = add_node(localpart(rgraph.graph)[1], label=sym)
        (n.idx, n.label)
    end
    node_tuple = fetch(f)
    return RemoteNodeRef(rgraph, node_tuple[1], node_tuple[2])
end

function add_edge(
    rgraph::RemoteOptiGraph,
    rnodes::RemoteNodeRef...;
    label = Symbol(rgraph.label, Symbol(".e"), length(rgraph.optiedges)+1)
)
    if has_edge(rgraph, Set(rnodes))
        redge = get_edge(rgraph, Set(rnodes))
    else
        subgraphs = [rgraph; all_subgraphs(rgraph)]
        if !(all(x -> x.remote_graph in subgraphs, rnodes))
            error("Remote Nodes do not belong to the remote graph or its subgrpahs")
        end

        redge = RemoteEdgeRef(rgraph, OrderedSet(collect(rnodes)), OrderedDict{MOI.ConstraintIndex, Plasmo.RemoteEdgeConstraintRef}(), OrderedDict{Plasmo.RemoteEdgeConstraintRef, JuMP.AbstractConstraint}(), label)
        push!(rgraph.optiedges, redge)
        rgraph.edge_data.optiedge_map[Set(collect(rnodes))] = redge
    end
    return redge
end

function has_edge(rgraph::RemoteOptiGraph, rnodes::Set{RemoteNodeRef})
    if haskey(rgraph.edge_data.optiedge_map, rnodes)
        return true
    else
        return false
    end
end

function get_edge(rgraph::RemoteOptiGraph, rnodes::Set{RemoteNodeRef})
    return rgraph.edge_data.optiedge_map[rnodes]
end

function JuMP.add_constraint(
    rgraph::RemoteOptiGraph, con::JuMP.AbstractConstraint, name::String=""
)
    rnodes = collect_nodes(JuMP.jump_function(con))
    @assert length(rnodes) > 0
    length(rnodes) > 1 || error("Cannot create a linking constraint on a single node")

    if all(n -> n.remote_graph == rgraph, rnodes)
        _build_constraint_ref(rgraph, con, name=name)
    else
        redge = add_edge(rgraph, rnodes...)
        con = JuMP.model_convert(redge, con)
        _build_constraint_ref(redge, con)
    end
    return nothing
end #TODO: Decide if JuMP.add_constraint should return a constraintref like the macros normally do; I don't think we want to fetch the cref from the remote though, so should decide if this should create a new remote ref or something like that

function _build_constraint_ref(rgraph::RemoteOptiGraph, con::JuMP.AbstractConstraint; name::String="")
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        new_expr = _convert_remote_to_local(rgraph, con.func)
        lcon = JuMP.ScalarConstraint(new_expr, con.set)
        cref = JuMP.add_constraint(lg, lcon, name)
        cref
    end
    return nothing
end

function _build_constraint_ref(redge::RemoteEdgeRef, con::JuMP.AbstractConstraint)
    # get moi function and set
    jump_func = JuMP.jump_function(con)
    moi_func = JuMP.moi_function(con)
    moi_set = JuMP.moi_set(con)

    # create constraint index and reference
    constraint_index = next_constraint_index(
        redge, typeof(moi_func), typeof(moi_set)
    )::MOI.ConstraintIndex{typeof(moi_func),typeof(moi_set)}
    cref = ConstraintRef(redge, constraint_index, JuMP.shape(con))

    redge.constraint_refs[constraint_index] = cref
    redge.constraints[cref] = con

    #TODO: define `containing_optigraphs` function like Plasmo does for OptiGraphs
    return nothing
end

function JuMP.add_constraint(
    rnode::RemoteNodeRef, con::JuMP.AbstractConstraint, name::String=""
)
    JuMP.model_convert(rnode, con)
    _build_constraint_ref(rnode, con)
    return nothing
end

function _build_constraint_ref(rnode::RemoteNodeRef, con::JuMP.VectorConstraint)
    error("Constraint $con is a vector constraint. Vector constraints are not yet supported in RemoteOptiGraphs")
end

function _build_constraint_ref(rnode::RemoteNodeRef, con::JuMP.ScalarConstraint)
    jump_func = JuMP.jump_function(con)
    _check_node_variables(rnode, jump_func)

    rgraph = rnode.remote_graph

    f = @spawnat rgraph.worker begin
        node = get_node(rgraph, rnode)
        new_expr = _convert_remote_to_local(rnode, con.func)
        lcon = JuMP.ScalarConstraint(new_expr, con.set)

        jump_func = JuMP.jump_function(lcon)
        moi_func = JuMP.moi_function(lcon)
        moi_set = JuMP.moi_set(lcon)

        constraint_index = next_constraint_index(
            node, typeof(moi_func), typeof(moi_set)
        )::MOI.ConstraintIndex{typeof(moi_func),typeof(moi_set)}

        cref = ConstraintRef(node, constraint_index, JuMP.shape(lcon))
        # add to each containing optigraph
        for graph in containing_optigraphs(node)
            MOI.add_constraint(graph_backend(graph), cref, jump_func, moi_set)
        end
    end
    return nothing#fetch(f)
end

function JuMP.is_valid(edge::RemoteEdgeRef, cref::ConstraintRef)
    return edge === JuMP.owner_model(cref)# && MOI.is_valid(graph_backend(edge), cref)
end

function get_edge(cref::RemoteEdgeConstraintRef)
    return JuMP.owner_model(cref)
end

function JuMP.set_name(rnode::RemoteNodeRef, label::Symbol)
    rgraph = rnode.remote_graph

    f = @spawnat rgraph.worker begin
        lnode = get_node(rgraph, rnode)
        lnode.label.x = label
    end

    rnode.node_label.x = label
end

#TODO: set_objective (node and graph)
#TODO: set_objective_sense (node and graph)
#https://github.com/plasmo-dev/Plasmo.jl/blob/b3081d52e06bfaf1adeee4ab04c190927d89c0ab/src/optigraph.jl#L1250-L1285
#TODO: Define constraint_object for edgerefs so that we can extend PlasmoBenders

function next_constraint_index(
    redge::RemoteEdgeRef, ::Type{F}, ::Type{S}
)::MOI.ConstraintIndex{F,S} where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    source_data = source_graph(redge).edge_data
    if !haskey(source_data.last_constraint_index, redge)
        source_data.last_constraint_index[redge] = 0
    end
    source_data.last_constraint_index[redge] += 1
    return MOI.ConstraintIndex{F,S}(source_data.last_constraint_index[redge])
end

function node_to_remote_ref(rgraph::RemoteOptiGraph, node::OptiNode) #ISSUE: can go from node to graph, but graph to node is hard
    return RemoteNodeRef(rgraph, node.idx, node.label)
end

function var_to_remote_ref(rgraph::RemoteOptiGraph, var::NodeVariableRef)
    rnode = node_to_remote_ref(rgraph, var.node)
    local_node = var.node
    graph = local_node.source_graph.x
    return RemoteVariableRef(rnode, var.index, Symbol(name(var)))
    #TODO: decide if the name should be a string or a symbol; I think I am switching between these a lot
end

function remote_ref_to_var(var::RemoteVariableRef)
    rnode = var.node
    rgraph = rnode.remote_graph
    lnode = get_node(rgraph, rnode)
    return NodeVariableRef(lnode, var.index)
end

function remote_ref_to_var(var::RemoteVariableRef, lnode::Plasmo.OptiNode)
    return NodeVariableRef(lnode, var.index)
end

function get_node(rgraph::RemoteOptiGraph, node::RemoteNodeRef)
    lg = local_graph(rgraph)

    #TODO: Make this more efficient
    for n in all_nodes(lg)
        if n.idx == node.node_idx
            return n
        end
    end
    error("Node $node not detected in RemoteGraph $rgraph")
end

function JuMP.add_variable(rnode::RemoteNodeRef, v::JuMP.ScalarVariable, name::String="")
    rvref = _add_remote_node_variable(rnode, v, name)
    return rvref
end

function _add_remote_node_variable(rnode::RemoteNodeRef, v::JuMP.ScalarVariable, name::String="")
    rgraph = rnode.remote_graph
    sym = Symbol(name)

    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        lnode = get_node(rgraph, rnode)
        nvref = JuMP.add_variable(lnode, v, name)
        lg.element_data.node_obj_dict[(lnode, sym)] = nvref
        nvref.index
    end
    moi_idx = fetch(f)

    return RemoteVariableRef(rnode, moi_idx, sym)
end

function add_variable(node::RemoteNodeRef, name::Symbol=Symbol(""))
    rgraph = node.remote_graph

    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        local_node = get_node(rgraph, node)
        new_var = @variable(local_node, base_name = String(name))
        lg.element_data.node_obj_dict[(local_node, name)] = new_var
        new_var.index
    end

    moi_idx = fetch(f)
    return RemoteVariableRef(node, moi_idx, name)
end

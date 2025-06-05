
function remote_node_to_local(rgraph::RemoteOptiGraph, rnode::RemoteNodeRef)
    lg = local_graph(rgraph)

    #TODO: Make this more efficient
    for n in all_nodes(lg)
        if n.idx == rnode.node_idx
            return n
        end
    end
    error("Node $rnode not detected in RemoteGraph $rgraph")
end

function get_node(graph::OptiGraph, sym::Symbol)
    for n in all_nodes(graph)
        if n.label.x == sym
            return n
        end 
    end
    error("Symbol $sym not saved on remotegraph")
end

function local_edge_to_remote(rgraph::RemoteOptiGraph, ledge::Plasmo.OptiEdge)
    rnodes = OrderedSet{Plasmo.RemoteNodeRef}()
    lnodes = ledge.nodes
    for node in lnodes
        rnode = local_node_to_remote(rgraph, node)
        push!(rnodes, rnode)
    end
    return RemoteEdgeRef(rgraph, rnodes, ledge.label)
end

function remote_edge_to_local(rgraph::RemoteOptiGraph, redge::Plasmo.RemoteOptiEdge)
    lgraph = local_part(rgraph)
    for edge in lgraph.optiedges #TODO: Make this approach more intuitive
        if edge.label == redge.label
            return edge
        end
    end
    for edge in all_edges(lgraph)
        if edge.label == redge.label
            return edge
        end
    end
    error("Edge $redge not found in remote graph")
end

function local_node_to_remote(rgraph::RemoteOptiGraph, node::OptiNode) #ISSUE: can go from node to graph, but graph to node is hard
    return RemoteNodeRef(rgraph, node.idx, Symbol[node.label.x])
end

function local_var_to_remote(rgraph::RemoteOptiGraph, var::NodeVariableRef)
    rnode = local_node_to_remote(rgraph, var.node)
    return RemoteVariableRef(rnode, var.index, Symbol(name(var)))
    #TODO: decide if the name should be a string or a symbol; I think I am switching between these a lot
end

function remote_var_to_local(var::RemoteVariableRef)
    rnode = var.node
    rgraph = rnode.remote_graph
    lnode = remote_node_to_local(rgraph, rnode)
    return NodeVariableRef(lnode, var.index)
end

function remote_var_to_local(var::RemoteVariableRef, lnode::Plasmo.OptiNode)
    return NodeVariableRef(lnode, var.index)
end

function _convert_remote_to_local(rgraph::RemoteOptiGraph, func::GenericAffExpr{Float64, Plasmo.RemoteVariableRef})
    new_func = GenericAffExpr{Float64, Plasmo.NodeVariableRef}(func.constant)
    for (var, val) in func.terms
        lnode = remote_node_to_local(rgraph, var.node)
        local_var = remote_var_to_local(var, lnode)
        new_func.terms[local_var] = val
    end
    return new_func
end

function _convert_remote_to_local(rnode::RemoteNodeRef, func::GenericAffExpr{Float64, Plasmo.RemoteVariableRef})
    lnode = remote_node_to_local(rnode.remote_graph, rnode)
    new_func = GenericAffExpr{Float64, Plasmo.NodeVariableRef}(func.constant)
    for (var, val) in func.terms
        local_var = remote_var_to_local(var, lnode)
        new_func.terms[local_var] = val
    end
    return new_func
end

function _convert_remote_to_local(rgraph::RemoteOptiGraph, func::GenericQuadExpr{Float64, Plasmo.RemoteVariableRef})
    new_aff = _convert_remote_to_local(rgraph, func.aff)
    new_terms = OrderedDict{UnorderedPair{NodeVariableRef}, Float64}()
    for (pair, val) in func.terms
        lnode1 = remote_node_to_local(rgraph, pair.a.node)
        local_var1 = remote_var_to_local(pair.a, lnode1)
        lnode2 = remote_node_to_local(rgraph, pair.b.node)
        local_var2 = remote_var_to_local(pair.b, lnode2)
        new_pair = UnorderedPair(local_var1, local_var2)
        new_terms[new_pair] = val
    end
    return GenericQuadExpr{Float64, Plasmo.NodeVariableRef}(new_aff, new_terms)
end

function _convert_remote_to_local(rnode::RemoteNodeRef, func::GenericQuadExpr{Float64, Plasmo.RemoteVariableRef})
    lnode = remote_node_to_local(rnode.remote_graph, rnode)
    new_aff = _convert_remote_to_local(rnode, func.aff)
    new_terms = OrderedDict{UnorderedPair{NodeVariableRef}, Float64}()
    for (pair, val) in func.terms
        local_var1 = remote_var_to_local(pair.a, lnode)
        local_var2 = remote_var_to_local(pair.b, lnode)
        new_pair = UnorderedPair(local_var1, local_var2)
        new_terms[new_pair] = val
    end
    return GenericQuadExpr{Float64, Plasmo.NodeVariableRef}(new_aff, new_terms)
end

function _convert_remote_to_local(robj::R, func::GenericNonlinearExpr{Plasmo.RemoteVariableRef}) where {R <: Union{RemoteNodeRef, RemoteOptiGraph}}
    V = Plasmo.NodeVariableRef
    ret = JuMP.GenericNonlinearExpr{V}(func.head, Any[])
    stack = Tuple{JuMP.GenericNonlinearExpr, Any}[]

    for arg in reverse(func.args)
        push!(stack, (ret, arg))
    end
    while !isempty(stack)
        parent, arg = pop!(stack)
        if arg isa GenericNonlinearExpr
            new_ret = JuMP.GenericNonlinearExpr{V}(arg.head, Any[])
            push!(parent.args, new_ret)
            for child in reverse(arg.args)
                push!(stack, (new_ret, _convert_remote_to_local(robj, child)))
            end
        else
            push!(parent.args, _convert_remote_to_local(robj, arg))
        end
    end
    return ret
end

function _convert_remote_to_local(rgraph::RemoteOptiGraph, func::RemoteVariableRef)
    lnode = remote_node_to_local(rgraph, func.node) #TODO: These "remote_node_to_local" calls will likely be slow if it gets called a lot; should address this in the future
    return remote_var_to_local(func, lnode)
end

function _convert_remote_to_local(rnode::RemoteNodeRef, func::RemoteVariableRef)
    lnode = remote_node_to_local(rnode.remote_graph, rnode) #TODO: These "remote_node_to_local" calls will likely be slow if it gets called a lot; should address this in the future
    return remote_var_to_local(func, lnode)
end

function _convert_remote_to_local(robj::R, func::NodeVariableRef) where {R <: Union{RemoteNodeRef, RemoteOptiGraph}}
    return func
end

function _convert_remote_to_local(robj::R, func::Float64) where {R <: Union{RemoteNodeRef, RemoteOptiGraph}}
    return func
end

function _convert_remote_to_local(robj::R, func::GenericNonlinearExpr{NodeVariableRef}) where {R <: Union{RemoteNodeRef, RemoteOptiGraph}}
    return func
end

function _convert_remote_to_local(robj::R, func::GenericAffExpr{Float64, NodeVariableRef}) where {R <: Union{RemoteNodeRef, RemoteOptiGraph}}
    return func
end

function _convert_remote_to_local(robj::R, func::GenericQuadExpr{Float64, NodeVariableRef}) where {R <: Union{RemoteNodeRef, RemoteOptiGraph}}
    return func
end

function _convert_local_to_remote(rgraph::RemoteOptiGraph, func::GenericAffExpr{Float64, Plasmo.NodeVariableRef})
    new_func = GenericAffExpr{Float64, Plasmo.RemoteVariableRef}(func.constant)
    for var in keys(func.terms)
        rvar = local_var_to_remote(rgraph, var)
        new_func.terms[rvar] = func.terms[var]
    end
    return new_func
end

function _convert_local_to_remote(rgraph::RemoteOptiGraph, func::GenericQuadExpr{Float64, Plasmo.NodeVariableRef})
    new_aff = _convert_local_to_remote(rgraph, func.aff)
    new_terms = OrderedDict{UnorderedPair{RemoteVariableRef}, Float64}()
    for pair in keys(func.terms)
        rvar1 = local_var_to_remote(rgraph, pair.a)
        rvar2 = local_var_to_remote(rgraph, pair.b)
        new_pair = UnorderedPair(rvar1, rvar2)
        new_terms[new_pair] = func.terms[pair]
    end
    return GenericQuadExpr{Float64, Plasmo.RemoteVariableRef}(new_aff, new_terms)
end

function _convert_local_to_remote(rgraph::RemoteOptiGraph, func::GenericNonlinearExpr{Plasmo.NodeVariableRef})
    V = Plasmo.RemoteVariableRef
    ret = JuMP.GenericNonlinearExpr{V}(func.head, Any[])
    stack = Tuple{JuMP.GenericNonlinearExpr, Any}[]

    for arg in reverse(func.args)
        push!(stack, (ret, arg))
    end
    while !isempty(stack)
        parent, arg = pop!(stack)
        if arg isa GenericNonlinearExpr
            new_ret = JuMP.GenericNonlinearExpr{V}(arg.head, Any[])
            push!(parent.args, new_ret)
            for child in reverse(arg.args)
                push!(stack, (new_ret, _convert_local_to_remote(rgraph, child)))
            end
        else
            push!(parent.args, _convert_local_to_remote(rgraph, arg))
        end
    end
    return ret
end

function _convert_local_to_remote(rgraph::RemoteOptiGraph, func::RemoteVariableRef)
    return func
end

function _convert_local_to_remote(rgraph::RemoteOptiGraph, func::NodeVariableRef)
    rvar = local_var_to_remote(rgraph, func)
    return rvar
end

function _convert_local_to_remote(rgraph::RemoteOptiGraph, func::Float64)
    return func
end

function _check_node_variables(rnode::RemoteNodeRef, jump_func::GenericAffExpr{Float64, Plasmo.RemoteVariableRef})
    for var in keys(jump_func.terms)
        if var.node != rnode
            error("Variable $var belongs to node $(var.node) but $rnode was specified")
        end
    end
    return nothing
end

function _check_node_variables(rnode::RemoteNodeRef, jump_func::GenericQuadExpr{Float64, Plasmo.RemoteVariableRef})
    for pair in keys(jump_func.terms)
        if pair.a.node != rnode
            error("Variable $(pair.a) belongs to node $(pair.a.node) but $rnode was specified")
        end
        if pair.b.node != rnode
            error("Variable $(pair.b) belongs to node $(pair.b.node) but $rnode was specified")
        end
    end
    _check_node_variables(rnode, jump_func.aff)
    return nothing
end

function _check_node_variables(rnode::RemoteNodeRef, jump_func::GenericNonlinearExpr{RemoteVariableRef})
    for arg in jump_func.args
        _check_node_variables(rnode, arg)
    end
    return nothing
end

function _check_node_variables(rnode::RemoteNodeRef, jump_func::RemoteVariableRef)
    if jump_func.node != rnode
        error("Variable $(jump_func) belongs to node $(jump_func.node) but $rnode was specified")
    end
end

function _check_node_variables(rnode::RemoteNodeRef, jump_func::Float64)
    return nothing
end

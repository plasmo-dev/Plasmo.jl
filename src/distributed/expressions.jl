function _convert_remote_to_local(rgraph::RemoteOptiGraph, func::GenericAffExpr{Float64, Plasmo.RemoteVariableRef})
    new_func = GenericAffExpr{Float64, Plasmo.NodeVariableRef}(func.constant)
    for var in keys(func.terms)
        lnode = get_node(rgraph, var.node)
        local_var = remote_ref_to_var(var, lnode)
        new_func.terms[local_var] = func.terms[var]
    end
    return new_func
end

function _convert_remote_to_local(rnode::RemoteNodeRef, func::GenericAffExpr{Float64, Plasmo.RemoteVariableRef})
    lnode = get_node(rnode.remote_graph, rnode)
    new_func = GenericAffExpr{Float64, Plasmo.NodeVariableRef}(func.constant)
    for var in keys(func.terms)
        local_var = remote_ref_to_var(var, lnode)
        new_func.terms[local_var] = func.terms[var]
    end
    return new_func
end

function _convert_remote_to_local(rgraph::RemoteOptiGraph, func::GenericQuadExpr{Float64, Plasmo.RemoteVariableRef})
    new_aff = _convert_remote_to_local(rgraph, func.aff)
    new_terms = OrderedDict{UnorderedPair{NodeVariableRef}, Float64}()
    for (pair, val) in func.terms
        lnode1 = get_node(rgraph, pair.a.node)
        local_var1 = remote_ref_to_var(pair.a, lnode1)
        lnode2 = get_node(rgraph, pair.b.node)
        local_var2 = remote_ref_to_var(pair.b, lnode2)
        new_pair = UnorderedPair(local_var1, local_var2)
        new_terms[new_pair] = val
    end
    return GenericQuadExpr{Float64, Plasmo.NodeVariableRef}(new_aff, new_terms)
end

function _convert_remote_to_local(rnode::RemoteNodeRef, func::GenericQuadExpr{Float64, Plasmo.RemoteVariableRef})
    lnode = get_node(rnode.remote_graph, rnode)
    new_aff = _convert_remote_to_local(rnode, func.aff)
    new_terms = OrderedDict{UnorderedPair{NodeVariableRef}, Float64}()
    for pair in keys(func.terms)
        local_var1 = remote_ref_to_var(pair.a, lnode)
        local_var2 = remote_ref_to_var(pair.b, lnode)
        new_pair = UnorderedPair(local_var1, local_var2)
        new_terms[new_pair] = func.terms[pair]
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
    lnode = get_node(rgraph, func.node) #TODO: These "get_node" calls will likely be slow if it gets called a lot; should address this in the future
    return remote_ref_to_var(func, lnode)
end

function _convert_remote_to_local(rnode::RemoteNodeRef, func::RemoteVariableRef)
    lnode = get_node(rnode.remote_graph, rnode) #TODO: These "get_node" calls will likely be slow if it gets called a lot; should address this in the future
    return remote_ref_to_var(func, lnode)
end

function _convert_remote_to_local(robj::R, func::NodeVariableRef) where {R <: Union{RemoteNodeRef, RemoteOptiGraph}}
    return func
end

function _convert_remote_to_local(robj::R, func::Float64) where {R <: Union{RemoteNodeRef, RemoteOptiGraph}}
    return func
end

function _convert_local_to_remote(rgraph::RemoteOptiGraph, func::GenericAffExpr{Float64, Plasmo.NodeVariableRef})
    new_func = GenericAffExpr{Float64, Plasmo.RemoteVariableRef}(func.constant)
    for var in keys(func.terms)
        rvar = var_to_remote_ref(rgraph, var)
        new_func.terms[rvar] = func.terms[var]
    end
    return new_func
end

function _convert_local_to_remote(rgraph::RemoteOptiGraph, func::GenericQuadExpr{Float64, Plasmo.NodeVariableRef})
    new_aff = _convert_local_to_remote(rgraph, func.aff)
    new_terms = OrderedDict{UnorderedPair{RemoteVariableRef}, Float64}()
    for pair in keys(func.terms)
        rvar1 = var_to_remote_ref(rgraph, pair.a)
        rvar2 = var_to_remote_ref(rgraph, pair.b)
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
    rvar = var_to_remote_ref(rgraph, func)
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

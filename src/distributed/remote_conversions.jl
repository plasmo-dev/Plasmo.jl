# This file contains functions used for converting remote objects to their corresponding
# local objects. These functions are primarily internal functions for Plasmo and won't be
# used often by users

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, pnode::ProxyNodeRef)
    return RemoteNodeRef(rgraph, pnode.node_idx, pnode.node_label)
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, redge::Plasmo.RemoteEdgeRef)
    pnodes = OrderedSet{Plasmo.ProxyNodeRef}()
    rnodes = redge.nodes
    for node in rnodes
        pnode = _convert_remote_to_proxy(rgraph, node)
        push!(pnodes, pnode)
    end
    return ProxyEdgeRef(pnodes, ledge.label)
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, pedge::Plasmo.ProxyEdgeRef)
    rnodes = OrderedSet{Plasmo.RemoteNodeRef}()
    for node in pedge.nodes
        rnode = _convert_proxy_to_remote(rgraph, node)
        push!(rnodes, rnode)
    end
    return RemoteEdgeRef(rgraph, rnodes, pedge.label)
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, rnode::RemoteNodeRef)
    return ProxyNodeRef(rnode.node_idx, rnode.node_label)
end

function _remote_var_to_proxy(rgraph::RemoteOptiGraph, var::RemoteVariableRef)
    pnode = _convert_remote_to_proxy(rgraph, var.node)
    return ProxyVariableRef(pnode, var.index, Symbol(name(var)))
    #TODO: decide if the name should be a string or a symbol; I think I am switching between these a lot
end

function _remote_var_to_proxy(var::RemoteVariableRef, pnode::ProxyNodeRef)
    return ProxyVariableRef(pnode, var.index, Symbol(name(var)))
end

function _remote_var_to_proxy(rgraph::RemoteOptiGraph, var::Array{RemoteVariableRef})
    rnode = first(var).node
    pnode = _convert_remote_to_proxy(rgraph, rnode)
    return map(x -> _remote_var_to_proxy(x, pnode), var)
end

function _proxy_var_to_remote(rgraph::RemoteOptiGraph, var::ProxyVariableRef)
    pnode = var.node
    rnode = _convert_proxy_to_remote(rgraph, pnode)
    return RemoteVariableRef(rnode, var.index, var.name)
end

function _proxy_var_to_remote(rgraph::RemoteOptiGraph, var::Array{ProxyVariableRef})
    pnode = first(var).node
    rnode = _convert_proxy_to_remote(rgraph, pnode)
    return map(x -> _proxy_var_to_remote(x, rnode), var)
end

function _proxy_var_to_remote(var::ProxyVariableRef, rnode::Plasmo.RemoteNodeRef)
    return RemoteVariableRef(rnode, var.index, var.name)
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, var::ProxyVariableRef)
    return _proxy_var_to_remote(rgraph, var)
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, var::Array{ProxyVariableRef})
    return _proxy_var_to_remote(rgraph, var)
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, var::RemoteVariableRef)
    return _remote_var_to_proxy(rgraph, var)
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, func::GenericAffExpr{Float64, Plasmo.ProxyVariableRef})
    new_func = GenericAffExpr{Float64, Plasmo.RemoteVariableRef}(func.constant)
    for (var, val) in func.terms
        rnode = _convert_proxy_to_remote(rgraph, var.node)
        remote_var = _proxy_var_to_remote(var, rnode)
        new_func.terms[remote_var] = val
    end
    return new_func
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, pnode::ProxyNodeRef, func::GenericAffExpr{Float64, Plasmo.ProxyVariableRef})
    rnode = _convert_proxy_to_remote(rgraph, pnode)
    new_func = GenericAffExpr{Float64, Plasmo.RemoteVariableRef}(func.constant)
    for (var, val) in func.terms
        remote_var = _proxy_var_to_remote(var, rnode)
        new_func.terms[remote_var] = val
    end
    return new_func
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, func::GenericQuadExpr{Float64, Plasmo.ProxyVariableRef})
    new_aff = _convert_proxy_to_remote(rgraph, func.aff)
    new_terms = OrderedDict{UnorderedPair{RemoteVariableRef}, Float64}()
    for (pair, val) in func.terms
        rnode1 = _convert_proxy_to_remote(rgraph, pair.a.node)
        remote_var1 = _proxy_var_to_remote(pair.a, rnode1)
        rnode2 = _convert_proxy_to_remote(rgraph, pair.b.node)
        remote_var2 = _proxy_var_to_remote(pair.b, rnode2)
        new_pair = UnorderedPair(remote_var1, remote_var2)
        new_terms[new_pair] = val
    end
    return GenericQuadExpr{Float64, Plasmo.RemoteVariableRef}(new_aff, new_terms)
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, pnode::ProxyNodeRef, func::GenericQuadExpr{Float64, Plasmo.ProxyVariableRef})
    rnode = _convert_proxy_to_remote(rgraph, pnode)
    new_aff = _convert_proxy_to_remote(rgraph, pnode, func.aff)
    new_terms = OrderedDict{UnorderedPair{RemoteVariableRef}, Float64}()
    for (pair, val) in func.terms
        remote_var1 = _proxy_var_to_remote(pair.a, rnode)
        remote_var2 = _proxy_var_to_remote(pair.b, rnode)
        new_pair = UnorderedPair(remote_var1, remote_var2)
        new_terms[new_pair] = val
    end
    return GenericQuadExpr{Float64, Plasmo.RemoteVariableRef}(new_aff, new_terms)
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, func::GenericNonlinearExpr{Plasmo.ProxyVariableRef})
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
                push!(stack, (new_ret, _convert_proxy_to_remote(rgraph, child)))
            end
        else
            push!(parent.args, _convert_proxy_to_remote(rgraph, arg))
        end
    end
    return ret
end

# function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, func::ProxyVariableRef)
#     rnode = _convert_proxy_to_remote(rgraph, func.node) #TODO: These "_convert_remote_to_local" calls will likely be slow if it gets called a lot; should address this in the future
#     return _proxy_var_to_remote(func, rnode)
# end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, pnode::ProxyNodeRef, func::ProxyVariableRef)
    rnode = _convert_proxy_to_remote(rgraph, pnode) #TODO: These "_convert_remote_to_local" calls will likely be slow if it gets called a lot; should address this in the future
    return _proxy_var_to_remote(func, rnode)
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, func::RemoteVariableRef)
    return func
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, func::Float64)
    return func
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, func::GenericNonlinearExpr{RemoteVariableRef})
    return func
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, func::GenericAffExpr{Float64, RemoteVariableRef})
    return func
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, func::GenericQuadExpr{Float64, RemoteVariableRef})
    return func
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, func::GenericAffExpr{Float64, Plasmo.RemoteVariableRef})
    new_func = GenericAffExpr{Float64, Plasmo.ProxyVariableRef}(func.constant)
    for var in keys(func.terms)
        pvar = _remote_var_to_proxy(rgraph, var)
        new_func.terms[pvar] = func.terms[var]
    end
    return new_func
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, func::GenericQuadExpr{Float64, Plasmo.RemoteVariableRef})
    new_aff = _convert_remote_to_proxy(rgraph, func.aff)
    new_terms = OrderedDict{UnorderedPair{ProxyVariableRef}, Float64}()
    for pair in keys(func.terms)
        pvar1 = _remote_var_to_proxy(rgraph, pair.a)
        pvar2 = _remote_var_to_proxy(rgraph, pair.b)
        new_pair = UnorderedPair(pvar1, pvar2)
        new_terms[new_pair] = func.terms[pair]
    end
    return GenericQuadExpr{Float64, Plasmo.ProxyVariableRef}(new_aff, new_terms)
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, func::GenericNonlinearExpr{Plasmo.RemoteVariableRef})
    V = Plasmo.ProxyVariableRef
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
                push!(stack, (new_ret, _convert_remote_to_proxy(rgraph, child)))
            end
        else
            push!(parent.args, _convert_remote_to_proxy(rgraph, arg))
        end
    end
    return ret
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, func::ProxyVariableRef)
    return func
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, func::Float64)
    return func
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, func::GenericNonlinearExpr{ProxyVariableRef})
    return func
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, func::GenericAffExpr{Float64, ProxyVariableRef})
    return func
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, func::GenericQuadExpr{Float64, ProxyVariableRef})
    return func
end

#function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, func::RemoteVariableRef)
#    pvar = _remote_var_to_proxy(lgraph, func)
#    return pvar
#end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, cref::JuMP.ConstraintRef)
    rmodel = cref.model
    pmodel = _convert_remote_to_proxy(rgraph, rmodel)
    return JuMP.ConstraintRef(pmodel, cref.index, cref.shape)
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, cref::JuMP.ConstraintRef)# TODO: specify constraintref better
    pmodel = cref.model
    rmodel = _convert_proxy_to_remote(rgraph, pmodel)
    return JuMP.ConstraintRef(rmodel, cref.index, cref.shape)
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

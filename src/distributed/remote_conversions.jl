# This file contains functions used for converting proxy variables/nodes/edges/expressions into 
# remote ones. Here "remote" refers to the objects stored on the main worker because they reference
# objects that are remote/distributed.

#################################### Nodes ####################################

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, pnode::ProxyNodeRef)
    return RemoteNodeRef(rgraph, pnode.node_idx, pnode.node_label)
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, rnode::RemoteNodeRef)
    return ProxyNodeRef(rnode.node_idx, rnode.node_label)
end

#################################### Edge ####################################

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, redge::Plasmo.RemoteEdgeRef)
    pnodes = OrderedSet{Plasmo.ProxyNodeRef}()
    rnodes = redge.nodes
    for node in rnodes
        pnode = _convert_remote_to_proxy(rgraph, node)
        push!(pnodes, pnode)
    end
    return ProxyEdgeRef(pnodes, redge.label)
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, pedge::Plasmo.ProxyEdgeRef)
    rnodes = OrderedSet{Plasmo.RemoteNodeRef}()
    for node in pedge.nodes
        rnode = _convert_proxy_to_remote(rgraph, node)
        push!(rnodes, rnode)
    end
    return RemoteEdgeRef(rgraph, rnodes, pedge.label)
end

#################################### Variables ####################################

# Maybe need to clean this up in the future; right now there are these
# remote_var_to_proxy functions that are later called by _convert_remote_to_proxy

function _remote_var_to_proxy(rgraph::RemoteOptiGraph, var::RemoteVariableRef)
    pnode = _convert_remote_to_proxy(rgraph, var.node)
    return ProxyVariableRef(pnode, var.index, Symbol(name(var)))
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

# Convert variables
function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, var::ProxyVariableRef)
    return _proxy_var_to_remote(rgraph, var)
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, var::RemoteVariableRef)
    return _remote_var_to_proxy(rgraph, var)
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, var::Array{ProxyVariableRef})
    return map(x -> _proxy_var_to_remote(rgraph, x), var)
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, var::Array{RemoteVariableRef})
    return map(x -> _remote_var_to_proxy(rgraph, x), var)
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, var::JuMP.Containers.SparseAxisArray{T, N, K}) where {T<:RemoteVariableRef,N,K<:Tuple{N, Any}}
    od = OrderedDict{K, T}(k => _remote_var_to_proxy(rgraph, v) for (k, v) in var)
    return JuMP.Containers.SparseAxisArray(od, var.names)    
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, var::JuMP.Containers.SparseAxisArray{T, N, K}) where {T<:ProxyVariableRef,N,K<:Tuple{N, Any}}
    od = OrderedDict{K, T}(k => _proxy_var_to_remote(rgraph, v) for (k, v) in var)
    return JuMP.Containers.SparseAxisArray(od, var.names)    
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, var::JuMP.Containers.DenseAxisArray{RemoteVariableRef})
    pvars = _convert_remote_to_proxy(rgraph, var.data)
    return JuMP.Containers.DenseAxisArray(pvars, var.axes, var.lookup, var.names)
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, var::JuMP.Containers.DenseAxisArray{ProxyVariableRef})
    rvars = _convert_proxy_to_remote(rgraph, var.data)
    return JuMP.Containers.DenseAxisArray(rvars, var.axes, var.lookup, var.names)
end

#################################### Expressions ####################################

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

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, func::Array{E}) where {E <: ProxyExpr}
    return map(x -> _convert_proxy_to_remote(rgraph, x), func)
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, func::Array{E}) where {E <: RemoteExpr}
    return map(x -> _convert_remote_to_proxy(rgraph, x), func)
end

#################################### Expression Supports ####################################

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, pnode::ProxyNodeRef, func::ProxyVariableRef)
    rnode = _convert_proxy_to_remote(rgraph, pnode)
    return _proxy_var_to_remote(func, rnode)
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, func::RemoteVariableRef)
    return func
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, func::Float64)
    return func
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, func::Array{Float64})
    return func
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, func::GenericAffExpr{Float64, RemoteVariableRef})
    return func
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, func::GenericQuadExpr{Float64, RemoteVariableRef})
    return func
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, func::GenericNonlinearExpr{RemoteVariableRef})
    return func
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, func::ProxyVariableRef)
    return func
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, func::Float64)
    return func
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, func::Array{Float64})
    return func
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, func::GenericAffExpr{Float64, ProxyVariableRef})
    return func
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, func::GenericQuadExpr{Float64, ProxyVariableRef})
    return func
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, func::GenericNonlinearExpr{ProxyVariableRef})
    return func
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, func::Nothing)
    return nothing
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, func::Nothing)
    return nothing
end

#################################### Constraints ####################################

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

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, func::Array{E}) where {E <: JuMP.ConstraintRef}
    return map(x -> _convert_remote_to_proxy(rgraph, x), func)
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, func::Array{E}) where {E <: JuMP.ConstraintRef}
    return map(x -> _convert_proxy_to_remote(rgraph, x), func)
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, var::JuMP.Containers.DenseAxisArray{T}) where {T <: JuMP.ConstraintRef}
    vars = _convert_remote_to_proxy(rgraph, var.data)
    return JuMP.Containers.DenseAxisArray(vars, var.axes, var.lookup, var.names)
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, var::JuMP.Containers.DenseAxisArray{T}) where {T <: JuMP.ConstraintRef}
    vars = _convert_proxy_to_remote(rgraph, var.data)
    return JuMP.Containers.DenseAxisArray(vars, var.axes, var.lookup, var.names)
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, var::JuMP.Containers.SparseAxisArray{T, N, K}) where {T<:JuMP.ConstraintRef,N,K<:Tuple{N, Any}}
    od = OrderedDict{K, T}(k => _convert_remote_to_proxy(rgraph, v) for (k, v) in var)
    return JuMP.Containers.SparseAxisArray(od, var.names)    
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, var::JuMP.Containers.SparseAxisArray{T, N, K}) where {T<:JuMP.ConstraintRef,N,K<:Tuple{N, Any}}
    od = OrderedDict{K, T}(k => _convert_proxy_to_remote(rgraph, v) for (k, v) in var)
    return JuMP.Containers.SparseAxisArray(od, var.names)    
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, var::JuMP.ScalarConstraint{E, S}) where {E<:ProxyExpr, S<:MOI.AbstractSet}
    pexpr = var.func
    rexpr = _convert_proxy_to_remote(rgraph, pexpr)
    return JuMP.ScalarConstraint(rexpr, var.set)
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, var::JuMP.ScalarConstraint{E, S}) where {E<:RemoteExpr, S<:MOI.AbstractSet}
    rexpr = var.func
    pexpr = _convert_proxy_to_remote(rgraph, rexpr)
    return JuMP.ScalarConstraint(pexpr, var.set)
end

#################################### Check Node Variables ####################################


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

#################################### Miscellaneous ####################################
# These get called when a user defines something like 
# @constraint(rg, con_name[some_set_that_has_no_entries], ....)
# this still needs to register the empty set to the model or it could cause
# issues for the user later

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, var::Array{T}) where {T<:JuMP.AbstractJuMPScalar}
    return map(x -> _convert_remote_to_proxy(rgraph, x), var)
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, var::Array{T}) where {T<:JuMP.AbstractJuMPScalar}
    return map(x -> _convert_proxy_to_remote(rgraph, x), var)
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, var::JuMP.Containers.DenseAxisArray{T}) where {T <: JuMP.AbstractJuMPScalar}
    vars = _convert_remote_to_proxy(rgraph, var.data)
    return JuMP.Containers.DenseAxisArray(vars, var.axes, var.lookup, var.names)
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, var::JuMP.Containers.DenseAxisArray{T}) where {T <: JuMP.AbstractJuMPScalar}
    vars = _convert_proxy_to_remote(rgraph, var.data)
    return JuMP.Containers.DenseAxisArray(vars, var.axes, var.lookup, var.names)
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, var::JuMP.Containers.SparseAxisArray{T, N, K}) where {T<:JuMP.AbstractJuMPScalar,N,K<:Tuple{N, Any}}
    od = OrderedDict{K, T}(k => _convert_remote_to_proxy(rgraph, v) for (k, v) in var)
    return JuMP.Containers.SparseAxisArray(od, var.names)    
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, var::JuMP.Containers.SparseAxisArray{T, N, K}) where {T<:JuMP.AbstractJuMPScalar,N,K<:Tuple{N, Any}}
    od = OrderedDict{K, T}(k => _convert_proxy_to_remote(rgraph, v) for (k, v) in var)
    return JuMP.Containers.SparseAxisArray(od, var.names)    
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, var::Array{T}) where {T}
    return map(x -> _convert_remote_to_proxy(rgraph, x), var)
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, var::Array{T}) where {T}
    return map(x -> _convert_proxy_to_remote(rgraph, x), var)
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, var::Set{T}) where {T}
    return Set([_convert_remote_to_proxy(rgraph, v) for v in var])
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, var::Set{T}) where {T}
    return Set([_convert_proxy_to_remote(rgraph, v) for v in var])
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, var::JuMP.Containers.DenseAxisArray)
    pvars = _convert_remote_to_proxy(rgraph, var.data)
    return JuMP.Containers.DenseAxisArray(pvars, var.axes, var.lookup, var.names)
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, var::JuMP.Containers.DenseAxisArray)
    rvars = _convert_proxy_to_remote(rgraph, var.data)
    return JuMP.Containers.DenseAxisArray(rvars, var.axes, var.lookup, var.names)
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, var::JuMP.Containers.SparseAxisArray{T, N, K}) where {T,N,K<:Tuple{N, Any}}
    od = OrderedDict{K, T}(k => _convert_remote_to_proxy(rgraph, v) for (k, v) in var)
    return JuMP.Containers.SparseAxisArray(od, var.names)    
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, var::JuMP.Containers.SparseAxisArray{T, N, K}) where {T,N,K<:Tuple{N, Any}}
    od = OrderedDict{K, T}(k => _convert_proxy_to_remote(rgraph, v) for (k, v) in var)
    return JuMP.Containers.SparseAxisArray(od, var.names)    
end

function _convert_remote_to_proxy(rgraph::RemoteOptiGraph, obj::Any)
    if !(isa(obj, Real))
        @warn(
           "Object of type $(typeof(obj)) is being passed to the remote worker and does not
           have a proxy equivalent set up and will be serialized in passing. This 
           could cause unexpected slow performance"
        )
    end
    return obj
end

function _convert_proxy_to_remote(rgraph::RemoteOptiGraph, obj::Any)
    if !(isa(obj, Real))
        @warn(
            "Object of type $(typeof(obj)) is being passed from the remote worker and does not
            have a proxy equivalent set up and will be serialized in passing. This 
            could cause unexpected slow performance"
        )
    end
    return obj
end
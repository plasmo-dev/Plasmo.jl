# This file contains functions used for converting proxy variables/nodes/edges/expressions into 
# local ones. Here "local" means what is local to the distributed worker (i.e., it is "local"
# with respect to the remote worker).

#################################### Nodes ####################################

function _convert_proxy_to_local(lgraph::OptiGraph, pnode::ProxyNodeRef)
    #TODO: Make this more efficient
    # find the node whose node_idx matchs the remote node
    for n in all_nodes(lgraph)
        if n.idx == pnode.node_idx
            return n
        end
    end
    error("Node $pnode not detected in OptiGraph $lgraph")
end

function _convert_local_to_proxy(lgraph::OptiGraph, node::OptiNode)
    return ProxyNodeRef(node.idx, node.label)
end

function get_node(graph::OptiGraph, sym::Symbol)
    # find the node whose symbol matches
    for n in all_nodes(graph)
        if n.label.x == sym
            return n
        end 
    end
    error("Symbol $sym not saved on OptiGraph")
end

#################################### Edge ####################################

function _convert_local_to_proxy(lgraph::OptiGraph, ledge::Plasmo.OptiEdge)
    pnodes = OrderedSet{Plasmo.ProxyNodeRef}()
    lnodes = ledge.nodes
    for node in lnodes
        pnode = _convert_local_to_proxy(lgraph, node)
        push!(pnodes, pnode)
    end
    return ProxyEdgeRef(pnodes, ledge.label)
end

function _convert_proxy_to_local(lgraph::OptiGraph, pedge::Plasmo.ProxyEdgeRef)
    #first search local edges
    for edge in lgraph.optiedges #TODO: Make this approach more intuitive
        if edge.label == pedge.label
            return edge
        end
    end
    # if the edge wasn't found in the local edges, look at all the edges (this includes nested edges)
    for edge in all_edges(lgraph)
        if edge.label == pedge.label
            return edge
        end
    end
    error("Edge $pedge not found in remote graph")
end

#################################### Variables ####################################

# Maybe need to clean this up in the future; right now there are these
# local_var_to_proxy functions that are later called by _convert_local_to_proxy
function _local_var_to_proxy(lgraph::OptiGraph, var::NodeVariableRef)
    pnode = _convert_local_to_proxy(lgraph, var.node)
    return ProxyVariableRef(pnode, var.index, Symbol(name(var)))
end

function _local_var_to_proxy(var::NodeVariableRef, pnode::ProxyNodeRef)
    return ProxyVariableRef(pnode, var.index)
end

function _local_var_to_proxy(lgraph::OptiGraph, var::Array{NodeVariableRef})
    lnode = first(var).node
    pnode = _convert_local_to_proxy(lgraph, lnode)
    return map(x -> _local_var_to_proxy(x, pnode), var)
end

function _proxy_var_to_local(lgraph::OptiGraph, var::ProxyVariableRef)
    pnode = var.node
    lnode = _convert_proxy_to_local(lgraph, pnode)
    return NodeVariableRef(lnode, var.index)
end

function _proxy_var_to_local(lgraph::OptiGraph, var::Array{ProxyVariableRef})
    pnode = first(var).node
    lnode = _convert_proxy_to_local(lgraph, pnode)
    return map(x -> _proxy_var_to_local(x, lnode), var)
end

function _proxy_var_to_local(var::ProxyVariableRef, lnode::Plasmo.OptiNode)
    return NodeVariableRef(lnode, var.index)
end

# Convert variables
function _convert_proxy_to_local(lgraph::OptiGraph, var::ProxyVariableRef)
    return _proxy_var_to_local(lgraph, var)
end

function _convert_local_to_proxy(lgraph::OptiGraph, var::NodeVariableRef)
    return _local_var_to_proxy(lgraph, var)
end

function _convert_proxy_to_local(lgraph::OptiGraph, var::Array{ProxyVariableRef})
    return map(x -> _proxy_var_to_local(lgraph, x), var)
end

function _convert_local_to_proxy(lgraph::OptiGraph, var::Array{NodeVariableRef})
    return map(x -> _local_var_to_proxy(lgraph, x), var)
end


function _convert_local_to_proxy(lgraph::OptiGraph, var::JuMP.Containers.SparseAxisArray{T, N, K}) where {T<:NodeVariableRef,N,K<:Tuple{N, Any}}
    od = OrderedDict{K, T}(k => _local_var_to_proxy(lgraph, v) for (k, v) in var)
    return SparseAxisArray(od, var.names)    
end

function _convert_proxy_to_local(lgraph::OptiGraph, var::JuMP.Containers.SparseAxisArray{T, N, K}) where {T<:ProxyVariableRef,N,K<:Tuple{N, Any}}
    od = OrderedDict{K, T}(k => _proxy_var_to_local(lgraph, v) for (k, v) in var)
    return SparseAxisArray(od, var.names)    

end

function _convert_local_to_proxy(lgraph::OptiGraph, var::JuMP.Containers.DenseAxisArray{NodeVariableRef})
    pvars = _convert_local_to_proxy(lgraph, var.data)
    return DenseAxisArray(pvars, var.axes, var.lookup, var.names)
end

function _convert_proxy_to_local(lgraph::OptiGraph, var::JuMP.Containers.DenseAxisArray{ProxyVariableRef})
    lvars = _convert_proxy_to_local(lgraph, var.data)
    return DenseAxisArray(lvars, var.axes, var.lookup, var.names)
end
#################################### Expressions ####################################

function _convert_proxy_to_local(lgraph::OptiGraph, func::GenericAffExpr{Float64, Plasmo.ProxyVariableRef})
    new_func = GenericAffExpr{Float64, Plasmo.NodeVariableRef}(func.constant)
    for (var, val) in func.terms
        lnode = _convert_proxy_to_local(lgraph, var.node)
        local_var = _proxy_var_to_local(var, lnode)
        new_func.terms[local_var] = val
    end
    return new_func
end

function _convert_proxy_to_local(lgraph::OptiGraph, pnode::ProxyNodeRef, func::GenericAffExpr{Float64, Plasmo.ProxyVariableRef})
    lnode = _convert_proxy_to_local(lgraph, pnode)
    new_func = GenericAffExpr{Float64, Plasmo.NodeVariableRef}(func.constant)
    for (var, val) in func.terms
        local_var = _proxy_var_to_local(var, lnode)
        new_func.terms[local_var] = val
    end
    return new_func
end

function _convert_proxy_to_local(lgraph::OptiGraph, func::GenericQuadExpr{Float64, Plasmo.ProxyVariableRef})
    new_aff = _convert_proxy_to_local(lgraph, func.aff)
    new_terms = OrderedDict{UnorderedPair{NodeVariableRef}, Float64}()
    for (pair, val) in func.terms
        lnode1 = _convert_proxy_to_local(lgraph, pair.a.node)
        local_var1 = _proxy_var_to_local(pair.a, lnode1)
        lnode2 = _convert_proxy_to_local(lgraph, pair.b.node)
        local_var2 = _proxy_var_to_local(pair.b, lnode2)
        new_pair = UnorderedPair(local_var1, local_var2)
        new_terms[new_pair] = val
    end
    return GenericQuadExpr{Float64, Plasmo.NodeVariableRef}(new_aff, new_terms)
end

function _convert_proxy_to_local(lgraph::OptiGraph, pnode::ProxyNodeRef, func::GenericQuadExpr{Float64, Plasmo.ProxyVariableRef})
    lnode = _convert_proxy_to_local(lgraph, pnode)
    new_aff = _convert_proxy_to_local(lgraph, pnode, func.aff)
    new_terms = OrderedDict{UnorderedPair{NodeVariableRef}, Float64}()
    for (pair, val) in func.terms
        local_var1 = _proxy_var_to_local(pair.a, lnode)
        local_var2 = _proxy_var_to_local(pair.b, lnode)
        new_pair = UnorderedPair(local_var1, local_var2)
        new_terms[new_pair] = val
    end
    return GenericQuadExpr{Float64, Plasmo.NodeVariableRef}(new_aff, new_terms)
end

function _convert_proxy_to_local(lgraph::OptiGraph, func::GenericNonlinearExpr{Plasmo.ProxyVariableRef})
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
                push!(stack, (new_ret, _convert_proxy_to_local(lgraph, child)))
            end
        else
            push!(parent.args, _convert_proxy_to_local(lgraph, arg))
        end
    end
    return ret
end

function _convert_local_to_proxy(lgraph::OptiGraph, func::GenericAffExpr{Float64, Plasmo.NodeVariableRef})
    new_func = GenericAffExpr{Float64, Plasmo.ProxyVariableRef}(func.constant)
    for var in keys(func.terms)
        pvar = _local_var_to_proxy(lgraph, var)
        new_func.terms[pvar] = func.terms[var]
    end
    return new_func
end

function _convert_local_to_proxy(lgraph::OptiGraph, func::GenericQuadExpr{Float64, Plasmo.NodeVariableRef})
    new_aff = _convert_local_to_proxy(lgraph, func.aff)
    new_terms = OrderedDict{UnorderedPair{ProxyVariableRef}, Float64}()
    for pair in keys(func.terms)
        pvar1 = _local_var_to_proxy(lgraph, pair.a)
        pvar2 = _local_var_to_proxy(lgraph, pair.b)
        new_pair = UnorderedPair(pvar1, pvar2)
        new_terms[new_pair] = func.terms[pair]
    end
    return GenericQuadExpr{Float64, Plasmo.ProxyVariableRef}(new_aff, new_terms)
end

function _convert_local_to_proxy(lgraph::OptiGraph, func::GenericNonlinearExpr{Plasmo.NodeVariableRef})
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
                push!(stack, (new_ret, _convert_local_to_proxy(lgraph, child)))
            end
        else
            push!(parent.args, _convert_local_to_proxy(lgraph, arg))
        end
    end
    return ret
end

function _convert_proxy_to_local(lgraph::OptiGraph, func::Array{E}) where {E <: ProxyExpr}
    return map(x -> _convert_proxy_to_local(lgraph, x), func)
end

function _convert_local_to_proxy(lgraph::OptiGraph, func::Array{E}) where {E <: NodeExpr}
    return map(x -> _convert_local_to_proxy(lgraph, x), func)
end

#################################### Expression Supports ####################################

function _convert_proxy_to_local(lgraph::OptiGraph, pnode::ProxyNodeRef, func::ProxyVariableRef)
    lnode = _convert_proxy_to_local(lgraph, pnode) #TODO: These "_convert_remote_to_local" calls will likely be slow if it gets called a lot; should address this in the future
    return _proxy_var_to_local(func, lnode)
end

function _convert_proxy_to_local(lgraph::OptiGraph, func::NodeVariableRef)
    return func
end

function _convert_proxy_to_local(lgraph::OptiGraph, func::Float64)
    return func
end

function _convert_proxy_to_local(lgraph::OptiGraph, func::Array{Float64})
    return func
end

function _convert_proxy_to_local(lgraph::OptiGraph, func::GenericAffExpr{Float64, NodeVariableRef})
    return func
end

function _convert_proxy_to_local(lgraph::OptiGraph, func::GenericQuadExpr{Float64, NodeVariableRef})
    return func
end

function _convert_proxy_to_local(lgraph::OptiGraph, func::GenericNonlinearExpr{NodeVariableRef})
    return func
end

function _convert_local_to_proxy(lgraph::OptiGraph, func::ProxyVariableRef)
    return func
end

function _convert_local_to_proxy(lgraph::OptiGraph, func::Float64)
    return func
end

function _convert_local_to_proxy(lgraph::OptiGraph, func::Array{Float64})
    return func
end

function _convert_local_to_proxy(lgraph::OptiGraph, func::GenericAffExpr{Float64, ProxyVariableRef})
    return func
end

function _convert_local_to_proxy(lgraph::OptiGraph, func::GenericQuadExpr{Float64, ProxyVariableRef})
    return func
end

function _convert_local_to_proxy(lgraph::OptiGraph, func::GenericNonlinearExpr{ProxyVariableRef})
    return func
end


#################################### Constraints ####################################


function _convert_local_to_proxy(lgraph::OptiGraph, cref::JuMP.ConstraintRef)
    lmodel = cref.model
    pmodel = _convert_local_to_proxy(lgraph, lmodel)
    return JuMP.ConstraintRef(pmodel, cref.index, cref.shape)
end

function _convert_proxy_to_local(lgraph::OptiGraph, cref::JuMP.ConstraintRef)# TODO: specify constraintref better
    pmodel = cref.model
    lmodel = _convert_proxy_to_local(lgraph, pmodel)
    return JuMP.ConstraintRef(lmodel, cref.index, cref.shape)
end

function _convert_local_to_proxy(lgraph::OptiGraph, func::Array{E}) where {E <: JuMP.ConstraintRef}
    return map(x -> _convert_local_to_proxy(lgraph, x), func)
end

function _convert_proxy_to_local(lgraph::OptiGraph, func::Array{E}) where {E <: JuMP.ConstraintRef}
    return map(x -> _convert_proxy_to_local(lgraph, x), func)
end

#################################### Catch and Warn ####################################

function _convert_proxy_to_local(lgraph::OptiGraph, obj)
    @error("Trying to move an object of type $(typeof(obj)) to the remote.
            This object type is not yet supported and could cause errors later.
            Please open an issue to have this ability added.")
    return nothing
end

function _convert_local_to_proxy(lgraph::OptiGraph, obj)
    @error("Trying to move an object of type $(typeof(obj)) to the remote.
            This object type is not yet supported and could cause errors later.
            Please open an issue to have this ability added.")
    return nothing
end
# Support for printing the Remote objects

function Base.string(rvar::RemoteVariableRef)
    return Base.string(rvar.node) * "[" * String(rvar.name) * "]"
end

Base.print(io::IO, rvar::RemoteVariableRef) = Base.print(io, Base.string(rvar))
Base.show(io::IO, rvar::RemoteVariableRef) = Base.print(io, rvar)

function JuMP.index(rvar::RemoteVariableRef) return rvar.index end
function JuMP.owner_model(rvar::RemoteVariableRef) return rvar.node end
function JuMP.name(rvar::RemoteVariableRef) return Base.string(rvar) end
function remote_graph(rvar::R) where {R <: Union{RemoteVariableRef, RemoteVariableArrayRef}}
    return rvar.node.remote_graph 
end

# enable accessing specific variables from a RemoteVariableRef; these actually don't get used under
# the current implementation, but these would make querying variables lighter on memory
function Base.getindex(rvar::RemoteVariableArrayRef, idx...)
    rgraph = remote_graph(rvar)
    darray = rgraph.graph
    rnode = rvar.node
    pnode = _convert_remote_to_proxy(rgraph, rnode)
    vname = rvar.name
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = _convert_proxy_to_local(lgraph, pnode)
        lvars = lnode[vname][idx...]

        var = _local_var_to_proxy(lgraph, lvars)
        var
    end
    pvars = fetch(f)
    return _proxy_var_to_remote(rgraph, pvars)
end

function JuMP.is_valid(rnode::RemoteNodeRef, rvar::RemoteVariableRef)
    if rvar.node == rnode
        return true
    else
        return false
    end
end

"""
    JuMP.local_variables(rgraph::RemoteOptiGraph)

Return all of the variables stored on the OptiGraph of the RemoteOptiGraph
including all sub-RemoteOptiGraphs
"""
function JuMP.all_variables(rgraph::RemoteOptiGraph)
    vars = local_variables(rgraph)
    for g in all_subgraphs(rgraph)
        vars = [vars; local_variables(g)]
    end
    return vars
end

"""
    JuMP.local_variables(rgraph::RemoteNodeRef)

Return all of the variables stored on the OptiNode represented by RemoteNodeRef
"""
function JuMP.all_variables(rnode::RemoteNodeRef)
    rgraph = rnode.remote_graph
    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)
    
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = _convert_proxy_to_local(lgraph, pnode)
        all_vars = JuMP.all_variables(lnode)
        [(var.index, Symbol(name(var))) for var in all_vars]
    end
    var_tuples = fetch(f)

    vars = [Plasmo.RemoteVariableRef(rnode, t[1], t[2]) for t in var_tuples]
    return vars
end

"""
    local_variables(rgraph::RemoteOptiGraph)

Return all of the variables stored on the OptiGraph of the RemoteOptiGraph
Does not fetch variables from subgraphs
"""
function local_variables(rgraph::RemoteOptiGraph)
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        all_vars = JuMP.all_variables(lgraph)
        [(var.node.idx, var.node.label, var.index, Symbol(name(var))) for var in all_vars] #Note: Building the remote ref on the remote does not keep the rgraph or rnode the same as before 
    end
    var_tuples = fetch(f)
    vars = [
        RemoteVariableRef(RemoteNodeRef(rgraph, t[1], t[2]), t[3], t[4]) for t in var_tuples
    ]
    return vars
end

"""
    JuMP.num_variables(rgraph::RemoteOptiGraph)

Return the total number of variables stored on the OptiGraph of the RemoteOptiGraph
including variables stored on all subgraphs
"""
function JuMP.num_variables(rgraph::RemoteOptiGraph)
    num_variables = num_local_variables(rgraph)
    for g in all_subgraphs(rgraph)
        num_variables += num_local_variables(g)
    end
    return num_variables
end

"""
    num_local_variables(rgraph::RemoteOptiGraph)

Return the number of variables stored on the OptiGraph of the RemoteOptiGraph
Does not include variables on subgraphs
"""
function num_local_variables(rgraph::RemoteOptiGraph)
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        JuMP.num_variables(lgraph)
    end
    return fetch(f)
end

function JuMP.value(rgraph::RemoteOptiGraph, rvar::RemoteVariableRef)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, rvar)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _convert_proxy_to_local(lgraph, pvar)
        JuMP.value(lgraph, lvar)
    end
    return fetch(f)
end

########## Extend many JuMP functions ##########
# most of these are just wrapped @spawnat calls

function JuMP.value(
    rgraph::RemoteOptiGraph, 
    rexpr::E
) where {E <: Union{GenericAffExpr, GenericQuadExpr, GenericNonlinearExpr}}
    darray = rgraph.graph
    pexpr = _convert_remote_to_proxy(rgraph, rexpr)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lexpr = _convert_proxy_to_local(lgraph, pexpr)
        JuMP.value(lgraph, lexpr)
    end
    return fetch(f)
end

function JuMP.has_upper_bound(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, rvar)

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _proxy_var_to_local(lgraph, pvar)
        JuMP.has_upper_bound(lvar)
    end
    return fetch(f)
end

function JuMP.has_lower_bound(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, rvar)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _proxy_var_to_local(lgraph, pvar)
        JuMP.has_lower_bound(lvar)
    end
    return fetch(f)
end

function JuMP.upper_bound(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, rvar)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _proxy_var_to_local(lgraph, pvar)
        JuMP.upper_bound(lvar)
    end
    return fetch(f)
end

function JuMP.lower_bound(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, rvar)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _proxy_var_to_local(lgraph, pvar)
        JuMP.lower_bound(lvar)
    end
    return fetch(f)
end

function JuMP.fix_value(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, rvar)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _proxy_var_to_local(lgraph, pvar)
        JuMP.fix_value(lvar)
    end
    return fetch(f)
end

function JuMP.is_binary(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, rvar)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _proxy_var_to_local(lgraph, pvar)
        JuMP.is_binary(lvar)
    end
    return fetch(f)
end

function JuMP.is_integer(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, rvar)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _proxy_var_to_local(lgraph, pvar)
        JuMP.is_integer(lvar)
    end
    return fetch(f)
end

function JuMP.is_fixed(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, rvar)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _proxy_var_to_local(lgraph, pvar)
        JuMP.is_fixed(lvar)
    end
    return fetch(f)
end

function JuMP.set_binary(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, rvar)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _proxy_var_to_local(lgraph, pvar)
        JuMP.set_binary(lvar)
    end
    return nothing
end

function JuMP.unset_binary(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, rvar)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _proxy_var_to_local(lgraph, pvar)
        JuMP.unset_binary(lvar)
    end
    return nothing
end

function JuMP.set_integer(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, rvar)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _proxy_var_to_local(lgraph, pvar)
        JuMP.set_integer(lvar)
    end
    return nothing
end

function JuMP.unset_integer(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, rvar)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _proxy_var_to_local(lgraph, pvar)
        JuMP.unset_integer(lvar)
    end
    return nothing
end

function JuMP.fix(rvar::RemoteVariableRef, value::Number; force::Bool = false)
    rgraph = remote_graph(rvar)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, rvar)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _proxy_var_to_local(lgraph, pvar)
        JuMP.fix(lvar, value; force = force)
    end
    return nothing
end

function JuMP.unfix(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, rvar)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _proxy_var_to_local(lgraph, pvar)
        JuMP.unfix(lvar)
    end
    return nothing
end

function JuMP.set_upper_bound(rvar::RemoteVariableRef, upper::Number)
    rgraph = remote_graph(rvar)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, rvar)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _proxy_var_to_local(lgraph, pvar)
        JuMP.set_upper_bound(lvar, upper)
    end
    return nothing
end

function JuMP.set_lower_bound(rvar::RemoteVariableRef, lower::Number)
    rgraph = remote_graph(rvar)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, rvar)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _proxy_var_to_local(lgraph, pvar)
        JuMP.set_lower_bound(lvar, lower)
    end
    return nothing
end

function JuMP.start_value(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, rvar)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _proxy_var_to_local(lgraph, pvar)
        JuMP.start_value(lvar)
    end
    return fetch(f)
end

function JuMP.set_start_value(rvar::RemoteVariableRef, value::Union{Nothing, Real})
    rgraph = remote_graph(rvar)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, rvar)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _proxy_var_to_local(lgraph, pvar)
        JuMP.set_start_value(lvar, value)
    end
    return nothing
end

function JuMP.FixRef(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, rvar)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _proxy_var_to_local(lgraph, pvar)
        cref = JuMP.FixRef(lvar)
        pcref = _convert_local_to_proxy(lgraph, cref)
        pcref
    end
    pcref = fetch(f)
    return _convert_proxy_to_local(rgraph, pcref)
end

function JuMP.LowerBoundRef(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, rvar)
        
    f = @spawnat rgraph.worker begin #TODO: Decide if this should test if there is a lower bound first; doing so results in a second call to the remote, rather than doing it all within the same @spawnat call
        lgraph = localpart(darray)[1]
        lvar = _proxy_var_to_local(lgraph, pvar)
        cref = JuMP.LowerBoundRef(lvar)
        pcref = _convert_local_to_proxy(lgraph, cref)
        pcref
    end
    pcref = fetch(f)
    return _convert_proxy_to_local(rgraph, pcref)
end

function JuMP.UpperBoundRef(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, rvar)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _proxy_var_to_local(lgraph, pvar)
        cref = JuMP.UpperBoundRef(lvar)
        pcref = _convert_local_to_proxy(lgraph, cref)
        pcref
    end
    pcref = fetch(f)
    return _convert_proxy_to_local(rgraph, pcref)
end

function JuMP.delete_lower_bound(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, rvar)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _proxy_var_to_local(lgraph, pvar)
        JuMP.delete_lower_bound(lvar)
    end
    return nothing
end

function JuMP.delete_upper_bound(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, rvar)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _proxy_var_to_local(lgraph, pvar)
        JuMP.delete_upper_bound(lvar)
    end
    return nothing
end

function JuMP.IntegerRef(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, rvar)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _proxy_var_to_local(lgraph, pvar)
        cref = JuMP.IntegerRef(lvar)
        pcref = _convert_local_to_proxy(lgraph, cref)
        pcref
    end
    pcref = fetch(f)
    return _convert_proxy_to_local(rgraph, pcref)
end

function JuMP.BinaryRef(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, rvar)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _proxy_var_to_local(lgraph, pvar)
        cref = JuMP.BinaryRef(lvar)
        pcref = _convert_local_to_proxy(lgraph, cref)
        pcref
    end
    pcref = fetch(f)
    return _convert_proxy_to_local(rgraph, pcref)
end

function variable_type(rgraph::RemoteOptiGraph)
    return RemoteVariableRef
end

function variable_type(graph::OptiGraph)
    return NodeVariableRef
end

function JuMP.delete(rnode::RemoteNodeRef, rvar::RemoteVariableRef)
    if rvar.node != rnode
        error("The variable reference you are trying to delete " * 
            "does not belong to the node"
        ) 
    end
    rgraph = rnode.remote_graph
    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)
    pvar = _convert_remote_to_proxy(rgraph, rvar)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = _convert_proxy_to_local(lgraph, pnode) # TODO: if obj_dict is added, make sure the name is deleted
        lvar = _convert_proxy_to_local(lgraph, pvar)
        JuMP.delete(lnode, lvar)
    end
    return nothing
end
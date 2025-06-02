function Base.string(rvar::RemoteVariableRef)
    return Base.string(rvar.node) * "[" * String(rvar.name) * "]"
end

Base.print(io::IO, rvar::RemoteVariableRef) = Base.print(io, Base.string(rvar))
Base.show(io::IO, rvar::RemoteVariableRef) = Base.print(io, rvar)

function JuMP.index(rvar::RemoteVariableRef) return rvar.index end
function JuMP.owner_model(rvar::RemoteVariableRef) return rvar.node end
function JuMP.name(rvar::RemoteVariableRef) return Base.string(rvar) end

function remote_graph(rvar::RemoteVariableRef)
    return rvar.node.remote_graph
end

function JuMP.is_valid(rnode::RemoteNodeRef, rvar::RemoteVariableRef)
    if rvar.node == rnode
        return true
    else
        return false
    end
end

function JuMP.all_variables(rgraph::RemoteOptiGraph)
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        all_vars = JuMP.all_variables(lg)
        [local_var_to_remote(rgraph, var) for var in all_vars] #TODO: Move the local_var_to_remote outside @spawnat? Not sure if this is being called in the right place. May need to rethink this
    end
    
    return fetch(f)
end

function JuMP.value(rgraph::RemoteOptiGraph, rvar::RemoteVariableRef)
    f = @spawnat rgraph.worker begin
        lgraph = local_graph(rgraph)
        lvar = remote_ref_to_var(rvar)
        JuMP.value(lgraph, lvar)
    end
    return fetch(f)
end

function JuMP.has_upper_bound(rvar::RemoteVariableRef)
    rgraph = rvar.node.remote_graph
    f = @spawnat rgraph.worker begin
        lvar = remote_ref_to_var(rvar)
        JuMP.has_upper_bound(lvar)
    end
    return fetch(f)
end

function JuMP.has_lower_bound(rvar::RemoteVariableRef)
    rgraph = rvar.node.remote_graph
    f = @spawnat rgraph.worker begin
        lvar = remote_ref_to_var(rvar)
        JuMP.has_lower_bound(lvar)
    end
    return fetch(f)
end

function JuMP.upper_bound(rvar::RemoteVariableRef)
    rgraph = rvar.node.remote_graph
    f = @spawnat rgraph.worker begin
        lvar = remote_ref_to_var(rvar)
        JuMP.upper_bound(lvar)
    end
    return fetch(f)
end

function JuMP.lower_bound(rvar::RemoteVariableRef)
    rgraph = rvar.node.remote_graph
    f = @spawnat rgraph.worker begin
        lvar = remote_ref_to_var(rvar)
        JuMP.lower_bound(lvar)
    end
    return fetch(f)
end

function JuMP.fix_value(rvar::RemoteVariableRef)
    rgraph = rvar.node.remote_graph
    f = @spawnat rgraph.worker begin
        lvar = remote_ref_to_var(rvar)
        JuMP.fix_value(lvar)
    end
    return fetch(f)
end

function JuMP.is_binary(rvar::RemoteVariableRef)
    rgraph = rvar.node.remote_graph
    f = @spawnat rgraph.worker begin
        lvar = remote_ref_to_var(rvar)
        JuMP.is_binary(lvar)
    end
    return fetch(f)
end

function JuMP.is_integer(rvar::RemoteVariableRef)
    rgraph = rvar.node.remote_graph
    f = @spawnat rgraph.worker begin
        lvar = remote_ref_to_var(rvar)
        JuMP.is_integer(lvar)
    end
    return fetch(f)
end

function JuMP.is_fixed(rvar::RemoteVariableRef)
    rgraph = rvar.node.remote_graph
    f = @spawnat rgraph.worker begin
        lvar = remote_ref_to_var(rvar)
        JuMP.is_fixed(lvar)
    end
    return fetch(f)
end

function JuMP.set_binary(rvar::RemoteVariableRef)
    rgraph = rvar.node.remote_graph
    f = @spawnat rgraph.worker begin
        lvar = remote_ref_to_var(rvar)
        JuMP.set_binary(lvar)
    end
    return fetch(f)
end

function JuMP.set_integer(rvar::RemoteVariableRef)
    rgraph = rvar.node.remote_graph
    f = @spawnat rgraph.worker begin
        lvar = remote_ref_to_var(rvar)
        JuMP.set_integer(lvar)
    end
    return fetch(f)
end

function JuMP.fix(rvar::RemoteVariableRef, value::Number; force::Bool = false)
    rgraph = rvar.node.remote_graph
    f = @spawnat rgraph.worker begin
        lvar = remote_ref_to_var(rvar)
        JuMP.fix(lvar, value; force = force)
    end
    return fetch(f)
end

function JuMP.unfix(rvar::RemoteVariableRef)
    rgraph = rvar.node.remote_graph
    f = @spawnat rgraph.worker begin
        lvar = remote_ref_to_var(rvar)
        JuMP.unfix(lvar)
    end
    return fetch(f)
end

function JuMP.set_upper_bound(rvar::RemoteVariableRef, upper::Number)
    rgraph = rvar.node.remote_graph
    f = @spawnat rgraph.worker begin
        lvar = remote_ref_to_var(rvar)
        JuMP.set_upper_bound(lvar, upper)
    end
    return fetch(f)
end

function JuMP.set_lower_bound(rvar::RemoteVariableRef, lower::Number)
    rgraph = rvar.node.remote_graph
    f = @spawnat rgraph.worker begin
        lvar = remote_ref_to_var(rvar)
        JuMP.set_lower_bound(lvar, lower)
    end
    return fetch(f)
end

function JuMP.FixRef(rvar::RemoteVariableRef)
    rgraph = rvar.node.remote_graph
    f = @spawnat rgraph.worker begin
        lvar = remote_ref_to_var
        cref = JuMP.FixRef(lvar)
        lnode = JuMP.owner_model(cref)
        rnode = local_node_to_remote(rgraph, lnode)
        rcref = ConstraintRef(rnode, cref.index, cref.shape)
        rcref
    end
    return fetch(f)
end
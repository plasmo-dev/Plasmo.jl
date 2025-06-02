function JuMP.all_variables(rgraph::RemoteOptiGraph)
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        all_vars = JuMP.all_variables(lg)
        [var_to_remote_ref(rgraph, var) for var in all_vars] #TODO: Move the var_to_remote_ref outside @spawnat? Not sure if this is being called in the right place. May need to rethink this
    end
    
    return fetch(f)
end


function JuMP.value(rvar::RemoteVariableRef)
    rgraph = rvar.node.remote_graph
    f = @spawnat rgraph.worker begin
        lvar = remote_ref_to_var(rvar)
        JuMP.value(lvar)
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
        rnode = node_to_remote_ref(rgraph, lnode)
        rcref = ConstraintRef(rnode, cref.index, cref.shape)
        rcref
    end
    return rcref
end



# Add other JuMP functions including dual

# need incident edges

# need to refactor utils.jl

# Add export statements
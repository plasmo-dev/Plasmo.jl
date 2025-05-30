function JuMP.value(rvar::RemoteVariableRef)
    rgraph = rvar.node.remote_graph
    f = @spawnat rgraph.worker begin
        lvar = remote_ref_to_var(rvar)
        JuMP.value(lvar)
    end
    return fetch(f)
end

# Add other JuMP functions including dual, fix, is_binary, etc. set_binary, is_intger, set_integer, upper_bound, lower_bound

# need to return FixRefs
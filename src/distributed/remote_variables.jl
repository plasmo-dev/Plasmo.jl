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
    rnode = rvar.node
    f = @spawnat rgraph.worker begin
        lnode = _convert_remote_to_local(rgraph, rnode)
        vname = rvar.name
        lvars = lnode[vname][idx...]
        if isa(lvars, Plasmo.NodeVariableRef)
            var = (lvars.index, Symbol(name(lvars)))
        else
            var = [(var.index, Symbol(name(var))) for var in lvars]
        end
        var
    end
    var_tuples = fetch(f)
    if isa(var_tuples, Tuple) #TODO: Make this code more elegant
        return RemoteVariableRef(rnode, var_tuples[1], var_tuples[2])
    else
        vars = [
            RemoteVariableRef(rnode, t[1], t[2]) for t in var_tuples
        ]
        return vars
    end
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
    local_variables(rgraph::RemoteOptiGraph)

Return all of the variables stored on the OptiGraph of the RemoteOptiGraph
Does not fetch variables from subgraphs
"""
function local_variables(rgraph::RemoteOptiGraph)
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        all_vars = JuMP.all_variables(lg)
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
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        JuMP.num_variables(lg)
    end
    return fetch(f)
end

function JuMP.value(rgraph::RemoteOptiGraph, rvar::RemoteVariableRef)
    f = @spawnat rgraph.worker begin
        lgraph = local_graph(rgraph)
        lvar = remote_var_to_local(rvar)
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
    f = @spawnat rgraph.worker begin
        lgraph = local_graph(rgraph)
        lexpr = _convert_remote_to_local(rgraph, rexpr)
        JuMP.value(lgraph, lexpr)
    end
    return fetch(f)
end

function JuMP.has_upper_bound(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    f = @spawnat rgraph.worker begin
        lvar = remote_var_to_local(rvar)
        JuMP.has_upper_bound(lvar)
    end
    return fetch(f)
end

function JuMP.has_lower_bound(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    f = @spawnat rgraph.worker begin
        lvar = remote_var_to_local(rvar)
        JuMP.has_lower_bound(lvar)
    end
    return fetch(f)
end

function JuMP.upper_bound(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    f = @spawnat rgraph.worker begin
        lvar = remote_var_to_local(rvar)
        JuMP.upper_bound(lvar)
    end
    return fetch(f)
end

function JuMP.lower_bound(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    f = @spawnat rgraph.worker begin
        lvar = remote_var_to_local(rvar)
        JuMP.lower_bound(lvar)
    end
    return fetch(f)
end

function JuMP.fix_value(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    f = @spawnat rgraph.worker begin
        lvar = remote_var_to_local(rvar)
        JuMP.fix_value(lvar)
    end
    return fetch(f)
end

function JuMP.is_binary(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    f = @spawnat rgraph.worker begin
        lvar = remote_var_to_local(rvar)
        JuMP.is_binary(lvar)
    end
    return fetch(f)
end

function JuMP.is_integer(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    f = @spawnat rgraph.worker begin
        lvar = remote_var_to_local(rvar)
        JuMP.is_integer(lvar)
    end
    return fetch(f)
end

function JuMP.is_fixed(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    f = @spawnat rgraph.worker begin
        lvar = remote_var_to_local(rvar)
        JuMP.is_fixed(lvar)
    end
    return fetch(f)
end

function JuMP.set_binary(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    f = @spawnat rgraph.worker begin
        lvar = remote_var_to_local(rvar)
        JuMP.set_binary(lvar)
    end
    return fetch(f)
end

function JuMP.unset_binary(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    f = @spawnat rgraph.worker begin
        lvar = remote_var_to_local(rvar)
        JuMP.unset_binary(lvar)
    end
    return fetch(f)
end

function JuMP.set_integer(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    f = @spawnat rgraph.worker begin
        lvar = remote_var_to_local(rvar)
        JuMP.set_integer(lvar)
    end
    return fetch(f)
end

function JuMP.unset_integer(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    f = @spawnat rgraph.worker begin
        lvar = remote_var_to_local(rvar)
        JuMP.unset_integer(lvar)
    end
    return fetch(f)
end

function JuMP.fix(rvar::RemoteVariableRef, value::Number; force::Bool = false)
    rgraph = remote_graph(rvar)
    f = @spawnat rgraph.worker begin
        lvar = remote_var_to_local(rvar)
        JuMP.fix(lvar, value; force = force)
    end
    return fetch(f)
end

function JuMP.unfix(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    f = @spawnat rgraph.worker begin
        lvar = remote_var_to_local(rvar)
        JuMP.unfix(lvar)
    end
    return fetch(f)
end

function JuMP.set_upper_bound(rvar::RemoteVariableRef, upper::Number)
    rgraph = remote_graph(rvar)
    f = @spawnat rgraph.worker begin
        lvar = remote_var_to_local(rvar)
        JuMP.set_upper_bound(lvar, upper)
    end
    return fetch(f)
end

function JuMP.set_lower_bound(rvar::RemoteVariableRef, lower::Number)
    rgraph = remote_graph(rvar)
    f = @spawnat rgraph.worker begin
        lvar = remote_var_to_local(rvar)
        JuMP.set_lower_bound(lvar, lower)
    end
    return fetch(f)
end

function JuMP.start_value(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    f = @spawnat rgraph.worker begin
        lvar = remote_var_to_local(rvar)
        JuMP.start_value(lvar)
    end
    return fetch(f)
end

function JuMP.set_start_value(rvar::RemoteVariableRef, value::Union{Nothing, Real})
    rgraph = remote_graph(rvar)
    f = @spawnat rgraph.worker begin
        lvar = remote_var_to_local(rvar)
        JuMP.set_start_value(lvar, value)
    end
    return fetch(f)
end

function JuMP.FixRef(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    f = @spawnat rgraph.worker begin
        lvar = remote_var_to_local(rvar)
        cref = JuMP.FixRef(lvar)
        lnode = JuMP.owner_model(cref)
        rnode = _convert_local_to_remote(rgraph, lnode)
        rcref = ConstraintRef(rnode, cref.index, cref.shape)
        rcref
    end
    return fetch(f)
end

function JuMP.LowerBoundRef(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    f = @spawnat rgraph.worker begin #TODO: Decide if this should test if there is a lower bound fist; doing so results in a second call to the remote, rather than doing it all within the same @spawnat call
        lvar = remote_var_to_local(rvar)
        cref = JuMP.LowerBoundRef(lvar)
        lnode = JuMP.owner_model(cref)
        rnode = _convert_local_to_remote(rgraph, lnode)
        rcref = ConstraintRef(rnode, cref.index, cref.shape)
        rcref
    end
    return fetch(f)
end

function JuMP.UpperBoundRef(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    f = @spawnat rgraph.worker begin
        lvar = remote_var_to_local(rvar)
        cref = JuMP.UpperBoundRef(lvar)
        lnode = JuMP.owner_model(cref)
        rnode = _convert_local_to_remote(rgraph, lnode)
        rcref = ConstraintRef(rnode, cref.index, cref.shape)
        rcref
    end
    return fetch(f)
end

function JuMP.delete_lower_bound(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    f = @spawnat rgraph.worker begin
        lvar = remote_var_to_local(rvar)
        JuMP.delete_lower_bound(lvar)
    end
    return fetch(f)
end

function JuMP.delete_upper_bound(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    f = @spawnat rgraph.worker begin
        lvar = remote_var_to_local(rvar)
        JuMP.delete_upper_bound(lvar)
    end
    return fetch(f)
end

function JuMP.IntegerRef(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    f = @spawnat rgraph.worker begin
        lvar = remote_var_to_local(rvar)
        cref = JuMP.IntegerRef(lvar)
        lnode = JuMP.owner_model(cref)
        rnode = _convert_local_to_remote(rgraph, lnode)
        rcref = ConstraintRef(rnode, cref.index, cref.shape)
        rcref
    end
    return fetch(f)
end

function JuMP.BinaryRef(rvar::RemoteVariableRef)
    rgraph = remote_graph(rvar)
    f = @spawnat rgraph.worker begin
        lvar = remote_var_to_local(rvar)
        cref = JuMP.BinaryRef(lvar)
        lnode = JuMP.owner_model(cref)
        rnode = _convert_local_to_remote(rgraph, lnode)
        rcref = ConstraintRef(rnode, cref.index, cref.shape)
        rcref
    end
    return fetch(f)
end

function variable_type(rgraph::RemoteOptiGraph)
    return RemoteVariableRef
end

function variable_type(graph::OptiGraph)
    return NodeVariableRef
end

# Support for printing the Remote objects

function Base.string(rnode::RemoteNodeRef)
    return String(rnode.node_label.x)
end
Base.print(io::IO, rnode::RemoteNodeRef) = Base.print(io, Base.string(rnode))
Base.show(io::IO, rnode::RemoteNodeRef) = Base.print(io, rnode)

function Base.string(rcref::RemoteNodeConstraintRef)
    return "RemoteNodeConstraintRef"
end
Base.print(io::IO, rcref::RemoteNodeConstraintRef) = Base.print(io, Base.string(rcref))
Base.show(io::IO, rcref::RemoteNodeConstraintRef) = Base.print(io, rcref)

function source_graph(rnode::RemoteNodeRef) return rnode.remote_graph end

###### Set Index for registering names to the OptiGraph stored on the RemoteOptiGraph ######
function Base.setindex!(rnode::RemoteNodeRef, value::JuMP.Containers.DenseAxisArray{RemoteVariableRef}, name::Symbol)
    rgraph = rnode.remote_graph
    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)
    pvar_array = map(x -> Plasmo.ProxyVariableRef(pnode, x.index, Symbol(name(x))), value.data)
    axes = value.axes
    lookup = value.lookup
    names = value.names

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = _convert_proxy_to_local(lgraph, pnode)
        key = (lnode, name)
        var_array = map(x -> Plasmo.NodeVariableRef(lnode, x.index), pvar_array)
        dense_array = DenseAxisArray(var_array, axes, lookup, names)

        lgraph.element_data.node_obj_dict[key] = dense_array
        nothing
    end
    return nothing
end

#TODO: Support sparse axis arrays

function Base.setindex!(rnode::RemoteNodeRef, value::Array{RemoteVariableRef}, name::Symbol)
    rgraph = rnode.remote_graph
    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)
    pvar_array = map(x -> Plasmo.ProxyVariableRef(pnode, x.index, Symbol(name(x))), value)

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = _convert_proxy_to_local(rgraph, pnode)
        key = (lnode, name)
        var_array = map(x -> Plasmo.NodeVariableRef(lnode, x.index), pvar_array)
        lgraph.element_data.node_obj_dict[key] = var_array
        nothing
    end
    return nothing
end

function Base.setindex!(rnode::RemoteNodeRef, value::RemoteVariableRef, name::Symbol) 
    rgraph = rnode.remote_graph
    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)
    var_idx = value.index

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = _convert_proxy_to_local(lgraph, pnode)
        key = (lnode, name)
        var = NodeVariableRef(lnode, var_idx)
        lgraph.element_data.node_obj_dict[key] = var
        nothing
    end
    return nothing
end

function Base.setindex!(rnode::RemoteNodeRef, value::E, name::Symbol) where {E <: Union{GenericAffExpr{Float64, Plasmo.RemoteVariableRef}, GenericQuadExpr{Float64, Plasmo.RemoteVariableRef}, GenericNonlinearExpr{Plasmo.RemoteVariableRef}}}
    rgraph = rnode.remote_graph
    darray = rgraph.graph
    _check_node_variables(rnode, value)
    pnode = _convert_remote_to_proxy(rgraph, rnode)
    pexpr = _convert_remote_to_proxy(rgraph, value)

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = _convert_proxy_to_local(lgraph, pnode)
        lexpr = _convert_proxy_to_local(lgraph, pexpr)
        key = (lnode, name)
        lgraph.element_data.node_obj_dict[key] = lexpr
    end
end

function Base.setindex!(rnode::RemoteNodeRef, value::JuMP.ConstraintRef, name::Symbol) #TODO: Make the constraintref more specific to remote objects
    rgraph = rnode.remote_graph
    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)
    pcref = _convert_remote_to_proxy(rgraph, value)

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = _convert_proxy_to_local(lgraph, pnode)
        lcref = _convert_proxy_to_local(lgraph, pcref)
        key = (lnode, name)
        lgraph.element_data.node_obj_dict[key] = lcref
    end
end

function Base.setindex!(rnode::RemoteNodeRef, value::Any, name::Symbol)
    @warn("Registering name of object of type $(typeof(value)) is not yet supported
    Please open an issue to have this added.")
    return nothing
    #TODO: Vector{ConstraintRef} does not work for name registry
end

# function _return_var_index(var::JuMP.Containers.DenseAxisArray)
#     return (var.axes #TODO: Support DenseAxisArrays
# end

function _return_var_index(lgraph::OptiGraph, pnode::ProxyNodeRef, var::Array{NodeVariableRef})
    var_array = map(x -> Plasmo.ProxyVariableRef(pnode, x.index, Symbol(name(var))), var)
    return var_array
end

function _return_var_index(lgraph::OptiGraph, pnode::ProxyNodeRef, var::NodeVariableRef)
    return ProxyVariableRef(pnode, var.index, Symbol(name(var)))
end

function _return_var_index(lgraph::OptiGraph, pnode::ProxyNodeRef, var::E) where {E <: Union{GenericAffExpr{Float64, Plasmo.NodeVariableRef}, GenericQuadExpr{Float64, Plasmo.NodeVariableRef}, GenericNonlinearExpr{Plasmo.NodeVariableRef}}}
    return _convert_local_to_proxy(lgraph, var)
end

function _return_var_index(lgraph::OptiGraph, pnode::ProxyNodeRef, var::JuMP.ConstraintRef)
    return _convert_local_to_proxy(lgraph, var)
end
#TODO: Can get rid of these _return_var_index 

# function _return_remote_var_object(rnode::RemoteNodeRef, idx::Array, sym::Symbol)
#     rvars = map(x -> RemoteVariableRef(rnode, x[1], x[2]), idx)
#     return rvars
# end

# function _return_remote_var_object(rnode::RemoteNodeRef, idx::MOI.VariableIndex, sym::Symbol)
#     return RemoteVariableRef(rnode, idx, sym)
# end

# function _return_remote_var_object(rnode::RemoteNodeRef, idx::E, sym::Symbol) where {E <: Union{GenericAffExpr{Float64, Plasmo.RemoteVariableRef}, GenericQuadExpr{Float64, Plasmo.RemoteVariableRef}, GenericNonlinearExpr{Plasmo.RemoteVariableRef}}}
#     return idx
# end

function _return_remote_var_object(rnode::RemoteNodeRef, idx::Tuple{CI, SS}, sym::Symbol) where {CI <: MOI.ConstraintIndex, SS <: JuMP.ScalarShape}
    return JuMP.ConstraintRef(rnode, idx[1], idx[2])
end

function Base.getindex(rnode::RemoteNodeRef, sym::Symbol) #TODO: Figure out how to make this more efficient; this returns a large set of variables
    rgraph = rnode.remote_graph
    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = Plasmo._convert_proxy_to_local(lgraph, pnode)
        pnode = _convert_local_to_proxy(lgraph, lnode)
        var = lnode[sym]
        _return_var_index(lgraph, pnode, var)
    end
    object = fetch(f)

    return _convert_proxy_to_remote(rgraph, object)
end

"""
    add_node(rgraph::RemoteOptiGraph)

Add a new optinode to `rgraph`. 
"""
function add_node(rgraph::RemoteOptiGraph)
    darray = rgraph.graph

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        n = add_node(lgraph)
        _convert_local_to_proxy(lgraph, n)
    end
    pnode = fetch(f)
    return _convert_proxy_to_remote(rgraph, pnode)
end

"""
    add_node(rgraph::RemoteOptiGraph, label::Symbol)

Add a new optinode to `rgraph` with the name `label`
"""
function add_node(rgraph::RemoteOptiGraph, label::Symbol) # TODO: Rethink whether this can be merged with previous function; the problem is that I want to keep the kwarg default of add_node(graph::OptiGraph), which also calls length(graph.optinodes); trying to use that same default argument in the add_node(rgraph::RemoteOptiGraph) means having to query the subgraph and get the number of nodes; probably not a big deal, but might require an extra fetch
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        n = add_node(lgraph, label=label)
        _convert_local_to_proxy(lgraph, n)
    end
    pnode = fetch(f)
    return _convert_proxy_to_remote(rgraph, pnode)
end

"""
    JuMP.add_constraint(rnode::RemoteNodeRef, con::JuMP.AbstractConstraint, name::String="")

Add a constraint `con` to the node which `rnode` represents. 
This function supports use of the @constraint JuMP macro.
"""
function JuMP.add_constraint(
    rnode::RemoteNodeRef, con::JuMP.AbstractConstraint, name::String=""
)
    abc = JuMP.model_convert(rnode, con)
    cref = _build_constraint_ref(rnode, con)
    return cref
end

# build constraint refs
# vectorconstraints are not yet supported for the RemoteOptiGraph case
function _build_constraint_ref(rnode::RemoteNodeRef, con::JuMP.VectorConstraint)
    error("Constraint $con is a vector constraint. Vector constraints are not yet supported in RemoteOptiGraphs")
end

function _build_constraint_ref(rnode::RemoteNodeRef, con::JuMP.ScalarConstraint)
    jump_func = JuMP.jump_function(con)
    _check_node_variables(rnode, jump_func)

    rgraph = rnode.remote_graph
    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)
    pexpr = _convert_remote_to_proxy(rgraph, con.func)
    con_set = con.set

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        node = _convert_proxy_to_local(lgraph, pnode)
        new_expr = _convert_proxy_to_local(lgraph, pexpr)
        lcon = JuMP.ScalarConstraint(new_expr, con.set)

        jump_func = JuMP.jump_function(lcon)
        moi_func = JuMP.moi_function(lcon)
        moi_set = JuMP.moi_set(lcon)

        constraint_index = next_constraint_index(
            node, typeof(moi_func), typeof(moi_set)
        )::MOI.ConstraintIndex{typeof(moi_func),typeof(moi_set)}

        cref = ConstraintRef(node, constraint_index, JuMP.shape(lcon))
        # add to each containing optigraph
        for graph in containing_optigraphs(node)
            MOI.add_constraint(graph_backend(graph), cref, jump_func, moi_set)
        end
        pcref = ConstraintRef(pnode, cref.index, cref.shape)
        pcref
    end
    pcref = fetch(f)
    return _convert_proxy_to_remote(rgraph, pcref)
end

function JuMP.delete(rnode::RemoteNodeRef, rcref::JuMP.ConstraintRef)
    if rcref.model != rnode
        error("The constraint reference you are trying to delete " * 
            "does not belong to the remote node"
        ) 
    end
    rgraph = rnode.remote_graph
    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)
    pcref = _convert_remote_to_proxy(rgraph, rcref)

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = _convert_proxy_to_local(lgraph, pnode) # TODO: if obj_dict is added, make sure the name is deleted
        lcref = _convert_proxy_to_local(lgraph, pcref)
        JuMP.delete(lnode, lcref)
    end
    return nothing
end

function JuMP.is_valid(node::RemoteNodeRef, cref::ConstraintRef)
    return node === JuMP.owner_model(cref)# && MOI.is_valid(graph_backend(edge), cref)
end

function JuMP.set_name(rnode::RemoteNodeRef, label::Symbol)
    rgraph = rnode.remote_graph
    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = _convert_proxy_to_local(lgraph, pnode)
        lnode.label.x = label
        if !(haskey(lgraph, label))
            lgraph[label] = lnode
        else
            error("Name $(label) is already registered to the model")
        end
    end

    rnode.node_label.x = label
    return nothing
    #return RemoteVariableRef(rgraph, rnode.node_idx, label)
end

"""
    JuMP.add_variable(rnode::RemoteNodeRef, v::JuMP.AbstractVariable, name::String="")

Add variable `v` to RemoteNodeRef `rnode`. This function supports use of the `@variable` JuMP macro.
Optionally add a `base_name` to the variable for printing.
"""
function JuMP.add_variable(rnode::RemoteNodeRef, v::JuMP.ScalarVariable, name::String="")
    rvref = _add_remote_node_variable(rnode, v, name)
    return rvref
end

function _add_remote_node_variable(rnode::RemoteNodeRef, v::JuMP.ScalarVariable, name::String="")
    rgraph = rnode.remote_graph
    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)
    sym = Symbol(name)

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = _convert_proxy_to_local(lgraph, pnode)
        nvref = JuMP.add_variable(lnode, v, name)
        nvref.index
    end
    moi_idx = fetch(f)

    return RemoteVariableRef(rnode, moi_idx, sym)
end

# objective support
function JuMP.set_objective(
    rnode::RemoteNodeRef, sense::MOI.OptimizationSense, func::JuMP.AbstractJuMPScalar
)
    rgraph = rnode.remote_graph
    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)
    pexpr = _convert_remote_to_proxy(rgraph, func)

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        new_func = _convert_proxy_to_local(lgraph, pexpr)
        lnode = _convert_proxy_to_local(lgraph, pnode)
        JuMP.set_objective(lnode, sense, new_func)
    end
    return func
end

function JuMP.set_objective_function(
    rnode::RemoteNodeRef, func::JuMP.AbstractJuMPScalar
)
    rgraph = rnode.remote_graph
    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)
    pexpr = _convert_remote_to_proxy(rgraph, func)

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        new_func = _convert_proxy_to_local(lgraph, pexpr)
        lnode = _convert_proxy_to_local(lgraph, pnode)
        JuMP.set_objective_function(lnode, new_func)
    end
    return func
end

function JuMP.set_objective_sense(
    rnode::RemoteNodeRef, sense::MOI.OptimizationSense
)
    rgraph = rnode.remote_graph
    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = _convert_proxy_to_local(lgraph, pnode)
        JuMP.set_objective_sense(lnode, sense)
    end
    return nothing
end

function JuMP.objective_value(rnode::RemoteNodeRef)
    rgraph = rnode.remote_graph
    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = _convert_proxy_to_local(lgraph, pnode)
        JuMP.objective_value(local_graph(lnode))
    end
    return fetch(f)
end

function JuMP.objective_function(rnode::RemoteNodeRef)
    rgraph = rnode.remote_graph
    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = _convert_proxy_to_local(lgraph, pnode)
        lobj_func = JuMP.objective_function(lnode)
        pobj_func = _convert_local_to_proxy(lgraph, lobj_func)
        pobj_func
    end
    pexpr = fetch(f)
    return _convert_proxy_to_remote(rgraph, pexpr)
end

function JuMP.dual(rgraph::RemoteOptiGraph, rcref::RemoteNodeConstraintRef)
    rnode = JuMP.owner_model(rcref)
    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = _convert_proxy_to_local(lgraph, pnode)
        cref = ConstraintRef(lnode, rcref.index, rcref.shape)
        JuMP.dual(lgraph, cref)
    end
    return fetch(f)
end

function JuMP.dual(rcref::RemoteNodeConstraintRef)
    rnode = JuMP.owner_model(rcref)
    rgraph = rnode.remote_graph
    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = node(lgraph, pnode)
        cref = ConstraintRef(lnode, rcref.index, rcref.shape)
        JuMP.dual(cref)
    end
    return fetch(f)
end

function node_type(rgraph::RemoteOptiGraph)
    return RemoteNodeRef
end

function node_type(graph::OptiGraph)
    return OptiNode
end

# These functions allow for making sure dictionary keys recognize two RemoteNodeRefs
# instantiated at different times will still be equal to one another
function Base.isequal(rnode1::RemoteNodeRef, rnode2::RemoteNodeRef)
    return rnode1.remote_graph == rnode2.remote_graph && rnode1.node_idx == rnode2.node_idx && rnode1.node_label.x == rnode2.node_label.x
end

function Base.:(==)(rnode1::RemoteNodeRef, rnode2::RemoteNodeRef)
    return rnode1.remote_graph == rnode2.remote_graph && rnode1.node_idx == rnode2.node_idx && rnode1.node_label.x == rnode2.node_label.x
end

function Base.hash(rnode::RemoteNodeRef, h::UInt)
    return hash((rnode.remote_graph, rnode.node_idx, rnode.node_label.x), h)
end
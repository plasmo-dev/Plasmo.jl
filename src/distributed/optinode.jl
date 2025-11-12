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

function source_graph(rnode::RemoteNodeRef)
    return rnode.remote_graph
end

###### Set Index for registering names to the OptiGraph stored on the RemoteOptiGraph ######
function Base.setindex!(rnode::RemoteNodeRef, value::Any, name::Symbol)
    rgraph = rnode.remote_graph
    t = (rnode, name)
    rgraph.element_data.node_obj_dict[t] = value

    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)
    pobj = _convert_remote_to_proxy(rgraph, value)

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = _convert_proxy_to_local(lgraph, pnode)
        lobj = _convert_proxy_to_local(lgraph, pobj)
        key = (lnode, name)
        lgraph.element_data.node_obj_dict[key] = lobj
    end
end

function Base.getindex(rnode::RemoteNodeRef, sym::Symbol)
    rgraph = rnode.remote_graph
    t = (rnode, sym)
    if haskey(rgraph.element_data.node_obj_dict, t)
        return rgraph.element_data.node_obj_dict[t]
    end
    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = Plasmo._convert_proxy_to_local(lgraph, pnode)
        var = lnode[sym]
        _convert_local_to_proxy(lgraph, var)
    end
    object = fetch(f)

    return _convert_proxy_to_remote(rgraph, object)
end

function Base.haskey(rnode::RemoteNodeRef, sym::Symbol)
    rgraph = rnode.remote_graph
    t = (rnode, sym)
    if haskey(rgraph.element_data.node_obj_dict, t)
        return true
    end
    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]

        lnode = Plasmo._convert_proxy_to_local(lgraph, pnode)
        haskey(lnode, sym)
    end
    return fetch(f)
end

"""
    add_node(rgraph::RemoteOptiGraph)

Add a new optinode to `rgraph`. 
"""
function add_node(rgraph::RemoteOptiGraph)
    darray = rgraph.graph
    wid = rgraph.worker

    f = @spawnat wid begin
        lgraph = localpart(darray)[1]
        n = add_node(lgraph; index=Symbol(UUIDs.uuid4()))
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
    error(
        "Constraint $con is a vector constraint. Vector constraints are not yet supported in RemoteOptiGraphs",
    )
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
        lcon = JuMP.ScalarConstraint(new_expr, con_set)

        moi_func = JuMP.moi_function(lcon)
        moi_set = JuMP.moi_set(lcon)

        constraint_index = next_constraint_index(
            node, typeof(moi_func), typeof(moi_set)
        )::MOI.ConstraintIndex{typeof(moi_func),typeof(moi_set)}

        cref = ConstraintRef(node, constraint_index, JuMP.shape(lcon))
        # add to each containing optigraph
        for graph in containing_optigraphs(node)
            MOI.add_constraint(graph_backend(graph), cref, new_expr, moi_set)
        end
        pcref = ConstraintRef(pnode, cref.index, cref.shape)
        pcref
    end
    pcref = fetch(f)
    return _convert_proxy_to_remote(rgraph, pcref)
end

function JuMP.delete(rnode::RemoteNodeRef, rcref::JuMP.ConstraintRef)
    if rcref.model != rnode
        error(
            "The constraint reference you are trying to delete " *
            "does not belong to the remote node",
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

function JuMP.num_constraints(
    rnode::RemoteNodeRef,
    func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
    set_type::Type{<:MOI.AbstractSet},
)
    rgraph = source_graph(rnode)
    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = _convert_proxy_to_local(lgraph, pnode)
        JuMP.num_constraints(ledge, func_type, set_type)
    end
    return fetch(f)
end

function JuMP.num_constraints(rnode::RemoteNodeRef; count_variable_in_set_constraints=true)
    rgraph = source_graph(rnode)
    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = _convert_proxy_to_local(lgraph, pnode)
        JuMP.num_constraints(
            lnode, count_variable_in_set_constraints=count_variable_in_set_constraints
        )
    end
    return fetch(f)
end

function JuMP.all_constraints(
    rnode::RemoteNodeRef,
    func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
    set_type::Type{<:MOI.AbstractSet},
)
    rgraph = source_graph(rnode)
    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = _convert_proxy_to_local(lgraph, pnode)
        lcons = JuMP.all_constraints(lnode, func_type, set_type)
        _convert_local_to_proxy(lgraph, lcons)
    end
    pcons = fetch(f)
    return _convert_proxy_to_remote(rgraph, pcons)
end

function JuMP.all_constraints(
    rnode::RemoteNodeRef; include_variable_in_set_constraints=false
)
    rgraph = source_graph(rnode)
    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = _convert_proxy_to_local(lgraph, pnode)
        lcons = JuMP.all_constraints(
            lnode, include_variable_in_set_constraints=include_variable_in_set_constraints
        )
        _convert_local_to_proxy(lgraph, lcons)
    end
    pcons = fetch(f)
    return _convert_proxy_to_remote(rgraph, pcons)
end

function JuMP.constraint_object(
    cref::ConstraintRef{R,MOI.ConstraintIndex{FuncType,SetType}}
) where {
    R<:Union{RemoteNodeRef,RemoteEdgeRef},
    FuncType<:MOI.AbstractScalarFunction,
    SetType<:MOI.AbstractScalarSet,
}
    rmodel = cref.model
    rgraph = source_graph(rmodel)
    darray = rgraph.graph
    pcref = _convert_remote_to_proxy(rgraph, cref)

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lcref = _convert_proxy_to_local(lgraph, pcref)
        lcon_obj = JuMP.constraint_object(lcref)
        _convert_local_to_proxy(lcon_obj)
    end
    pcon_obj = fetch(f)
    return _convert_proxy_to_remote(rgraph, pcon_obj)
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
function JuMP.add_variable(rnode::RemoteNodeRef, v::JuMP.AbstractVariable, name::String="")
    rvref = _add_remote_node_variable(rnode, v, name)
    return rvref
end

function _add_remote_node_variable(
    rnode::RemoteNodeRef, v::JuMP.AbstractVariable, name::String=""
)
    rgraph = rnode.remote_graph
    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)
    sym = Symbol(name)

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = _convert_proxy_to_local(lgraph, pnode)
        nvref = JuMP.add_variable(lnode, v, name)
        _convert_local_to_proxy(lgraph, nvref)
    end
    pvref = fetch(f)

    return _convert_proxy_to_remote(rgraph, pvref)
end

function JuMP.num_variables(rnode::RemoteNodeRef)
    rgraph = rnode.remote_graph
    darray = rgraph.graph
    pnode = _convert_remote_to_proxy(rgraph, rnode)

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = _convert_proxy_to_local(lgraph, pnode)
        JuMP.num_variables(lnode)
    end
    return fetch(f)
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

function JuMP.set_objective_function(rnode::RemoteNodeRef, func::JuMP.AbstractJuMPScalar)
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

function JuMP.set_objective_sense(rnode::RemoteNodeRef, sense::MOI.OptimizationSense)
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

function JuMP.objective_sense(rnode::RemoteNodeRef)
    rgraph = source_graph(rnode)
    pnode = _convert_remote_to_proxy(rgraph, rnode)
    darray = rgraph.graph

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = _convert_proxy_to_local(lgraph, pnode)
        JuMP.objective_sense(lnode)
    end
    return fetch(f)
end

function has_objective(rnode::RemoteNodeRef)
    rgraph = source_graph(rnode)
    pnode = _convert_remote_to_proxy(rgraph, rnode)
    darray = rgraph.graph

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = _convert_proxy_to_local(lgraph, pnode)
        Plasmo.has_objective(lnode)
    end
    return fetch(f)
end

function JuMP.objective_function_type(rnode::RemoteNodeRef)
    rgraph = source_graph(rnode)
    pnode = _convert_remote_to_proxy(rgraph, rnode)
    darray = rgraph.graph

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = _convert_proxy_to_local(lgraph, pnode)
        JuMP.objective_function_type(lnode)
    end
    return fetch(f)
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
        lnode = _convert_proxy_to_local(lgraph, pnode)
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
    return rnode1.node_idx == rnode2.node_idx
end

function Base.:(==)(rnode1::RemoteNodeRef, rnode2::RemoteNodeRef)
    return rnode1.node_idx == rnode2.node_idx
end

function Base.hash(rnode::RemoteNodeRef, h::UInt)
    return hash((rnode.node_idx), h)
end

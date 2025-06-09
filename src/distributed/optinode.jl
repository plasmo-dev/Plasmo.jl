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

function Base.setindex!(rnode::RemoteNodeRef, value::JuMP.Containers.DenseAxisArray{RemoteVariableRef}, name::Symbol)
    rgraph = rnode.remote_graph

    f = @spawnat rgraph.worker begin
        lgraph = local_graph(rgraph)
        lnode = remote_node_to_local(rgraph, rnode)
        key = (lnode, name)
        var_array = map(x -> Plasmo.NodeVariableRef(lnode, x.index), value.data)
        dense_array = DenseAxisArray(var_array, value.axes, value.lookup, value.names)

        lgraph.element_data.node_obj_dict[key] = dense_array
        nothing
    end
    return nothing
end

#TODO: Support sparse axis arrays

function Base.setindex!(rnode::RemoteNodeRef, value::Array{RemoteVariableRef}, name::Symbol)
    rgraph = rnode.remote_graph

    f = @spawnat rgraph.worker begin
        lgraph = local_graph(rgraph)
        lnode = remote_node_to_local(rgraph, rnode)
        key = (lnode, name)
        var_array = map(x -> Plasmo.NodeVariableRef(lnode, x.index), value)
        lgraph.element_data.node_obj_dict[key] = var_array
        nothing
    end
    return nothing
end

function Base.setindex!(rnode::RemoteNodeRef, value::RemoteVariableRef, name::Symbol) 
    rgraph = rnode.remote_graph

    f = @spawnat rgraph.worker begin
        lgraph = local_graph(rgraph)
        lnode = remote_node_to_local(rgraph, rnode)
        key = (lnode, name)
        var = NodeVariableRef(lnode, value.index)
        lgraph.element_data.node_obj_dict[key] = var
        nothing
    end
    return nothing
end

function Base.setindex!(rnode::RemoteNodeRef, value::Any, name::Symbol)
    return nothing
end

function _return_var_index(var::JuMP.Containers.DenseAxisArray)
    return var.axes
end

function _return_var_index(var::Array{NodeVariableRef})
    return size(var)
end

function _return_var_index(var::NodeVariableRef)
    return var.index
end

function _return_remote_var_object(rnode::RemoteNodeRef, idx::Tuple, sym::Symbol)
    return RemoteVariableArrayRef(rnode, sym, idx)
end

# function _return_remote_var_object(rnode::RemoteNodeRef, idx::Int, sym::Symbol)
#     return RemoteVariableArrayRef(rnode, sym, idx)
# end

function _return_remote_var_object(rnode::RemoteNodeRef, idx::MOI.VariableIndex, sym::Symbol)
    return RemoteVariableRef(rnode, idx, sym)
end

function Base.getindex(rnode::RemoteNodeRef, sym::Symbol) #TODO: Figure out how to make this more efficient; this returns a large set of variables
    rgraph = rnode.remote_graph
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        local_node = Plasmo.remote_node_to_local(rgraph, rnode)
        # if sym == :_theta
        #     println(local_node)
        #     println(lg.element_data.node_obj_dict)
        # end
        var = local_node[sym]
        _return_var_index(var)
    end
    idx = fetch(f)

    return _return_remote_var_object(rnode, idx, sym)# RemoteVariableRef(rnode, moi_idx, sym)
end

function add_node(rgraph::RemoteOptiGraph)
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        n = add_node(lg)
        (n.idx, n.label)
    end
    node_tuple = fetch(f)
    return RemoteNodeRef(rgraph, node_tuple[1], node_tuple[2])
end

function add_node(rgraph::RemoteOptiGraph, label::Symbol) # TODO: Rethink whether this can be merged with previous function; the problem is that I want to keep the kwarg default of add_node(graph::OptiGraph), which also calls length(graph.optinodes); trying to use that same default argument in the add_node(rgraph::RemoteOptiGraph) means having to query the subgraph and get the number of nodes; probably not a big deal, but might require an extra fetch
    f = @spawnat rgraph.worker begin
        n = add_node(localpart(rgraph.graph)[1], label=label)
        (n.idx, n.label)
    end
    node_tuple = fetch(f)
    return RemoteNodeRef(rgraph, node_tuple[1], node_tuple[2])
end

function JuMP.add_constraint(
    rnode::RemoteNodeRef, con::JuMP.AbstractConstraint, name::String=""
)
    JuMP.model_convert(rnode, con)
    cref = _build_constraint_ref(rnode, con)
    return nothing
end

function _build_constraint_ref(rnode::RemoteNodeRef, con::JuMP.VectorConstraint)
    error("Constraint $con is a vector constraint. Vector constraints are not yet supported in RemoteOptiGraphs")
end

function _build_constraint_ref(rnode::RemoteNodeRef, con::JuMP.ScalarConstraint)
    jump_func = JuMP.jump_function(con)
    _check_node_variables(rnode, jump_func)

    rgraph = rnode.remote_graph

    f = @spawnat rgraph.worker begin
        node = remote_node_to_local(rgraph, rnode)
        new_expr = _convert_remote_to_local(rnode, con.func)
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
        rcref = ConstraintRef(rnode, cref.index, cref.shape)
        rcref
    end
    return fetch(f)
end

function JuMP.is_valid(node::RemoteNodeRef, cref::ConstraintRef)
    return node === JuMP.owner_model(cref)# && MOI.is_valid(graph_backend(edge), cref)
end

function JuMP.set_name(rnode::RemoteNodeRef, label::Symbol)
    rgraph = rnode.remote_graph

    f = @spawnat rgraph.worker begin
        lnode = remote_node_to_local(rgraph, rnode)
        lnode.label.x = label
    end

    rnode.node_label.x = label
    return nothing
    #return RemoteVariableRef(rgraph, rnode.node_idx, label)
end

function JuMP.add_variable(rnode::RemoteNodeRef, v::JuMP.ScalarVariable, name::String="")
    rvref = _add_remote_node_variable(rnode, v, name)
    return rvref
end

function _add_remote_node_variable(rnode::RemoteNodeRef, v::JuMP.ScalarVariable, name::String="")
    rgraph = rnode.remote_graph
    sym = Symbol(name)

    f = @spawnat rgraph.worker begin
        lnode = remote_node_to_local(rgraph, rnode)
        nvref = JuMP.add_variable(lnode, v, name)
        nvref.index
    end
    moi_idx = fetch(f)

    return RemoteVariableRef(rnode, moi_idx, sym)
end

function add_variable(rnode::RemoteNodeRef, name::Symbol=Symbol(""))
    rgraph = rnode.remote_graph

    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        local_node = remote_node_to_local(rgraph, rnode)
        new_var = @variable(local_node, base_name = String(name))
        new_var.index
    end

    moi_idx = fetch(f)
    return RemoteVariableRef(rnode, moi_idx, name)
end


function JuMP.set_objective(
    rnode::RemoteNodeRef, sense::MOI.OptimizationSense, func::JuMP.AbstractJuMPScalar
)
    rgraph = rnode.remote_graph
    f = @spawnat rgraph.worker begin
        new_func = _convert_remote_to_local(rnode, func)
        lnode = remote_node_to_local(rgraph, rnode)
        JuMP.set_objective(lnode, sense, new_func)
    end
    return func
end

function JuMP.set_objective_function(
    rnode::RemoteNodeRef, func::JuMP.AbstractJuMPScalar
)
    rgraph = rnode.remote
    f = @spawnat rgraph.worker begin
        new_func = _convert_remote_to_local(rnode, func)
        lnode = remote_node_to_local(rgraph, rnode)
        JuMP.set_objective_function(lnode, new_func)
    end
    return func
end

function JuMP.set_objective_sense(
    rnode::RemoteNodeRef, sense::MOI.OptimizationSense
)
    rgraph = rnode.remote
    f = @spawnat rgraph.worker begin
        lnode = remote_node_to_local(rgraph, rnode)
        JuMP.set_objective_sense(lnode, sense)
    end
    return nothing
end

function JuMP.objective_value(rnode::RemoteNodeRef)
    rgraph = rnode.remote_graph
    f = @spawnat rgraph.worker begin
        lnode = remote_node_to_local(rgraph, rnode)
        JuMP.objective_value(local_graph(lnode))
    end
    return fetch(f)
end

function JuMP.objective_function(rnode::RemoteNodeRef)
    rgraph = rnode.remote_graph
    f = @spawnat rgraph.worker begin
        lnode = remote_node_to_local(rgraph, rnode)
        lobj_func = JuMP.objective_function(lnode)
        robj_func = _convert_local_to_remote(rgraph, lobj_func)
        robj_func
    end
    return fetch(f)
end

function JuMP.dual(rgraph::RemoteOptiGraph, rcref::RemoteNodeConstraintRef)
    rnode = JuMP.owner_model(rcref)
    f = @spawnat rgraph.worker begin
        lgraph = local_graph(rgraph)
        lnode = node(rgraph, rnode)
        cref = ConstraintRef(lnode, rcref.index, rcref.shape)
        JuMP.dual(lgraph, cref)
    end
    return fetch(f)
end

function JuMP.dual(rcref::RemoteNodeConstraintRef)
    rnode = JuMP.owner_model(rcref)
    rgraph = rnode.remote_graph
    f = @spawnat rgraph.worker begin
        lnode = node(rgraph, rnode)
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

function Base.isequal(rnode1::RemoteNodeRef, rnode2::RemoteNodeRef)
    return rnode1.remote_graph == rnode2.remote_graph && rnode1.node_idx == rnode2.node_idx && rnode1.node_label.x == rnode2.node_label.x
end

function Base.:(==)(rnode1::RemoteNodeRef, rnode2::RemoteNodeRef)
    return rnode1.remote_graph == rnode2.remote_graph && rnode1.node_idx == rnode2.node_idx && rnode1.node_label.x == rnode2.node_label.x
end

function Base.hash(rnode::RemoteNodeRef, h::UInt)
    return hash((rnode.remote_graph, rnode.node_idx, rnode.node_label.x), h)
end
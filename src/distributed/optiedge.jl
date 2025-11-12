# Enable visualizing/printing a RemoteEdgeRef
function Base.string(redge::RemoteEdgeRef)
    return String(redge.label)
end
Base.print(io::IO, redge::RemoteEdgeRef) = Base.print(io, Base.string(redge))
Base.show(io::IO, redge::RemoteEdgeRef) = Base.print(io, redge)

# Enable visualizing/printing a InterWorkerEdge
function Base.string(redge::InterWorkerEdge)
    return String(redge.label)
end
Base.print(io::IO, redge::InterWorkerEdge) = Base.print(io, Base.string(redge))
Base.show(io::IO, redge::InterWorkerEdge) = Base.print(io, redge)

# Enable visualizing a remote constraint ref
function Base.string(rcref::InterWorkerEdgeConstraintRef)
    redge = rcref.model
    rcref = redge.constraints[rcref]
    mode = JuMP.MIME("text/plain")
    return JuMP.function_string(mode, rcref) * " " * JuMP.in_set_string(mode, rcref)
end

function Base.string(rcref::RemoteEdgeConstraintRef)
    return "RemoteEdgeConstraintRef"
end
Base.print(io::IO, rcref::RemoteEdgeConstraintRef) = Base.print(io, Base.string(rcref))
Base.show(io::IO, rcref::RemoteEdgeConstraintRef) = Base.print(io, rcref)

Base.print(io::IO, rcref::InterWorkerEdgeConstraintRef) = Base.print(io, Base.string(rcref))
Base.show(io::IO, rcref::InterWorkerEdgeConstraintRef) = Base.print(io, Base.string(rcref))

# return source graph (will be a RemoteOptiGraph)
function source_graph(redge::InterWorkerEdge)
    return redge.remote_graph
end
function source_graph(redge::RemoteEdgeRef)
    return redge.remote_graph
end

function Base.setindex!(edge::InterWorkerEdge, value::Any, name::Symbol)
    t = (edge, name)
    source_graph(edge).element_data.edge_obj_dict[t] = value
    return nothing
end

function Base.getindex(edge::InterWorkerEdge, name::Symbol)
    t = (edge, name)
    return source_graph(edge).element_data.edge_obj_dict[t]
end

# Extend Constraint Object call
function JuMP.constraint_object(
    con_ref::ConstraintRef{InterWorkerEdge,MOI.ConstraintIndex{FuncType,SetType}}
) where {FuncType<:MOI.AbstractScalarFunction,SetType<:MOI.AbstractScalarSet}
    model = con_ref.model
    return model.constraints[con_ref]
end

function edge_object_dictionary(edge::InterWorkerEdge)
    d = source_graph(edge).element_data.edge_obj_dict
    return filter(p -> p.first[1] == edge, d)
end

function JuMP.object_dictionary(edge::InterWorkerEdge)
    d = source_graph(edge).element_data.edge_obj_dict
    return d
end

# Add an edge for a set of RemoteNodeRefs
function add_edge(
    rgraph::RemoteOptiGraph,
    rnodes::RemoteNodeRef...;
    label=Symbol(rgraph.label, Symbol(".e"), length(rgraph.optiedges)+1),
)
    if has_edge(rgraph, Set(rnodes)) # check if the edge exists
        redge = get_edge(rgraph, Set(rnodes))
    else
        # if not, check that the nodes are in the graph or subgraphs
        subgraphs = [rgraph; all_subgraphs(rgraph)]
        if !(all(x -> x.remote_graph in subgraphs, rnodes))
            error("Remote nodes do not belong to the remote graph or its subgraphs")
        end

        # build new edge
        redge = InterWorkerEdge(
            rgraph,
            OrderedSet(collect(rnodes)),
            OrderedDict{MOI.ConstraintIndex,Plasmo.InterWorkerEdgeConstraintRef}(),
            OrderedDict{Plasmo.InterWorkerEdgeConstraintRef,JuMP.AbstractConstraint}(),
            label,
        )
        push!(rgraph.optiedges, redge)
        rgraph.element_data.optiedge_map[Set(collect(rnodes))] = redge
    end
    return redge
end

# Check if an edge exists between the given nodes
function has_edge(rgraph::RemoteOptiGraph, rnodes::Set{RemoteNodeRef})
    if haskey(rgraph.element_data.optiedge_map, rnodes)
        return true
    elseif all(x -> x.remote_graph == rgraph, rnodes)
        darray = rgraph.graph
        pnodes = _convert_remote_to_proxy(rgraph, rnodes)
        f = @spawnat rgraph.worker begin
            lgraph = localpart(darray)[1]
            lnodes = _convert_proxy_to_local(lgraph, pnodes)
            Plasmo.has_edge(lgraph, lnodes)
        end
        return fetch(f)
    else
        return false
    end
end

"""
    get_edge(rgraph::RemoteOptiGraph, rnodes::Set{<:RemoteNodeRef})

Retrieve the remote optiedge in `rgraph` that connects `rnodes`.
"""
function get_edge(rgraph::RemoteOptiGraph, rnodes::Set{RemoteNodeRef})
    if haskey(rgraph.element_data.optiedge_map, rnodes)
        return rgraph.element_data.optiedge_map[rnodes]
    elseif all(x -> x.remote_graph == rgraph, rnodes)
        darray = rgraph.graph
        pnodes = _convert_remote_to_proxy(rgraph, rnodes)
        f = @spawnat rgraph.worker begin
            lgraph = localpart(darray)[1]
            lnodes = _convert_proxy_to_local(lgraph, pnodes)
            ledge = Plasmo.get_edge(lgraph, lnodes)
            _convert_local_to_proxy(lgraph, ledge)
        end
        pedge = fetch(f)
        return _convert_proxy_to_remote(rgraph, pedge)
    else
        error("Edge not found in the graph")
    end
end

"""
    get_edge(rgraph::RemoteOptiGraph, rnodes::RemoteNodeRef...)

Convenience method. Retrieve the remote optiedge in `rgraph` that connects `rnodes`.
"""
function get_edge(rgraph::RemoteOptiGraph, rnodes::RemoteNodeRef...)
    return get_edge(rgraph, Set(rnodes))
end

"""
    get_edge_by_index(rgraph::RemoteOptiGraph, idx::Int64)

Retrieve the remote optiedge in `graph` that corresponds to the given index.
"""
function get_edge_by_index(rgraph::RemoteOptiGraph, idx::Int64)
    return collect(rgraph.optiedges)[idx]
end

"""
    local_edges(rgraph::RemoteOptiGraph)

Retrieve the edges that exists in `rgraph`. Does not return edges that exist in subgraphs.
"""
function local_edges(rgraph::RemoteOptiGraph)
    return collect(rgraph.optiedges)
end

"""
    num_local_edges(rgraph::RemoteOptiGraph)::Int

Return the number of local edges in the optigraph `rgraph`.
"""
function num_local_edges(rgraph::RemoteOptiGraph)
    return length(rgraph.optiedges)
end

"""
    all_edges(rgraph::RemoteOptiGraph)::Vector{<:InterWorkerEdge}

Recursively collect all remote optiedges in `rgraph` by traversing each of its subgraphs.
"""
function all_edges(rgraph::RemoteOptiGraph)
    edges = collect(rgraph.optiedges)
    for subgraph in rgraph.subgraphs
        edges = [edges; collect(all_edges(subgraph))]
    end
    return edges
end

"""
    num_edges(graph::RemoteOptiGraph)::Int

Return the total number of edges in `graph` by recursively checking subgraphs.
"""
function num_edges(rgraph::RemoteOptiGraph)
    n_edges = num_local_edges(rgraph)
    for subgraph in rgraph.subgraphs
        n_edges += num_edges(subgraph)
    end
    return n_edges
end

"""
    all_remote_edges(rgraph::RemoteOptiGraph)::Vector{<:InterWorkerEdge}

Collect all remote optiedges in `rgraph` by traversing each of its subgraphs. 
Returns only `RemoteEdgeRef`s, not `InterWorkerEdge`s.
"""
function all_remote_edges(rgraph::RemoteOptiGraph)
    edges = local_remote_edges(rgraph)
    for subgraph in rgraph.subgraphs
        edges = [edges; all_remote_edges(subgraph)]
    end
    return edges
end

"""
    num_remote_edges(graph::RemoteOptiGraph)::Int

Return the total number of edges on the graph and subgraphs of `graph`.
Returns only the number of `RemoteEdgeRef`s, not `InterWorkerEdge`s
"""
function num_remote_edges(rgraph::RemoteOptiGraph)
    n_edges = num_local_remote_edges(rgraph)
    for subgraph in rgraph.subgraphs
        n_edges += num_remote_edges(subgraph)
    end
    return n_edges
end

"""
    local_remote_edges(rgraph::RemoteOptiGraph)

Retrieve the edges that exist in `rgraph`. Does not return edges that exist
in subgraphs, and does not return any `InterWorkerEdges`, only `RemoteEdgeRef`s
"""
function local_remote_edges(rgraph::RemoteOptiGraph)
    darray = rgraph.graph

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        ledges = all_edges(lgraph)
        _convert_local_to_proxy(lgraph, ledges)
    end
    pedges = fetch(f)
    return _convert_proxy_to_remote(rgraph, pedges)
end

"""
    num_local_remote_edges(rgraph::RemoteOptiGraph)::Int

Retrieve the number of edges that exist in `rgraph`. Does not return edges that exist in subgraphs, and does not count `InterWorkerEdges`, only `RemoteEdgeRef`s
"""
function num_local_remote_edges(rgraph::RemoteOptiGraph)
    darray = rgraph.graph

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        num_edges(lgraph)
    end
    return fetch(f)
end

function all_nodes(edge::E) where {E<:Union{InterWorkerEdge,RemoteEdgeRef}}
    return collect(edge.nodes)
end

function JuMP.is_valid(edge::InterWorkerEdge, cref::ConstraintRef)
    return edge === JuMP.owner_model(cref)
end

function JuMP.is_valid(edge::RemoteEdgeRef, cref::ConstraintRef)
    return edge === JuMP.owner_model(cref)
end

function get_edge(cref::InterWorkerEdgeConstraintRef)
    return JuMP.owner_model(cref)
end

function get_edge(cref::RemoteEdgeConstraintRef)
    return JuMP.owner_model(cref)
end

function get_constraint(rcref::InterWorkerEdgeConstraintRef)
    redge = rcref.model
    @assert haskey(redge.constraints, rcref)
    return redge.constraints[rcref]
end

function next_constraint_index(
    redge::InterWorkerEdge, ::Type{F}, ::Type{S}
)::MOI.ConstraintIndex{F,S} where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    source_data = source_graph(redge).element_data
    if !haskey(source_data.last_constraint_index, redge)
        source_data.last_constraint_index[redge] = 0
    end
    source_data.last_constraint_index[redge] += 1
    return MOI.ConstraintIndex{F,S}(source_data.last_constraint_index[redge])
end

# build the constraint reference for an edge
function _build_constraint_ref(redge::InterWorkerEdge, con::JuMP.AbstractConstraint)
    # get moi function and set
    moi_func = JuMP.moi_function(con)
    moi_set = JuMP.moi_set(con)

    # create constraint index and reference
    constraint_index = next_constraint_index(
        redge, typeof(moi_func), typeof(moi_set)
    )::MOI.ConstraintIndex{typeof(moi_func),typeof(moi_set)}
    cref = ConstraintRef(redge, constraint_index, JuMP.shape(con))

    redge.constraint_refs[constraint_index] = cref
    redge.constraints[cref] = con

    return cref
end

function JuMP.num_constraints(
    redge::RemoteEdgeRef,
    func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
    set_type::Type{<:MOI.AbstractSet},
)
    rgraph = source_graph(redge)
    darray = rgraph.graph
    pedge = _convert_remote_to_proxy(rgraph, redge)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        ledge = _convert_proxy_to_local(lgraph, pedge)
        JuMP.num_constraints(ledge, func_type, set_type)
    end
    return fetch(f)
end

function JuMP.num_constraints(redge::RemoteEdgeRef)
    rgraph = source_graph(redge)
    darray = rgraph.graph
    pedge = _convert_remote_to_proxy(rgraph, redge)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        ledge = _convert_proxy_to_local(lgraph, pedge)
        JuMP.num_constraints(ledge)
    end
    return fetch(f)
end

function JuMP.all_constraints(
    redge::RemoteEdgeRef,
    func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
    set_type::Type{<:MOI.AbstractSet},
)
    rgraph = source_graph(redge)
    darray = rgraph.graph
    pedge = _convert_remote_to_proxy(rgraph, redge)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        ledge = _convert_proxy_to_local(lgraph, pedge)
        lcons = JuMP.all_constraints(ledge, func_type, set_type)
        _convert_local_to_proxy(lgraph, lcons)
    end
    pcons = fetch(f)
    return _convert_proxy_to_remote(rgraph, pcons)
end

function JuMP.all_constraints(redge::RemoteEdgeRef)
    rgraph = source_graph(redge)
    darray = rgraph.graph
    pedge = _convert_remote_to_proxy(rgraph, redge)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        ledge = _convert_proxy_to_local(lgraph, pedge)
        lcons = JuMP.all_constraints(ledge)
        _convert_local_to_proxy(lgraph, lcons)
    end
    pcons = fetch(f)
    return _convert_proxy_to_remote(rgraph, pcons)
end

function JuMP.num_constraints(
    redge::InterWorkerEdge,
    func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
    set_type::Type{<:MOI.AbstractSet},
)
    rgraph = source_graph(redge)
    all_crefs = collect(keys(redge.constraints))
    ncrefs = 0
    for cref in all_crefs
        con = redge.constraints[cref]
        if isa(con.func, func_type) && isa(con.set, set_type)
            ncrefs += 1
        end
    end
    return ncrefs
end

function JuMP.num_constraints(redge::InterWorkerEdge)
    return length(redge.constraints)
end

function JuMP.all_constraints(
    redge::InterWorkerEdge,
    func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
    set_type::Type{<:MOI.AbstractSet},
)
    rgraph = source_graph(redge)
    all_crefs = collect(keys(redge.constraints))
    cons = InterWorkerEdgeConstraintRef[]
    for cref in all_crefs
        con = redge.constraints[cref]
        if isa(con.func, func_type) && isa(con.set, set_type)
            push!(cons, cref)
        end
    end
    return cons
end

function JuMP.all_constraints(redge::InterWorkerEdge)
    return collect(keys(redge.constraints))
end

"""
    Plasmo.incident_edges(rgraph::RemoteOptiGraph)

Get the set of incident edges to a given `rgraph`. This requires the `rgraph` to have 
a parent graph, which is what will be search to get the incident edges
"""
function incident_edges(rgraph::RemoteOptiGraph)
    !(isnothing(rgraph.parent_graph)) || error("Given graph does not have parent graph")
    parent_graph = rgraph.parent_graph
    parent_edges = parent_graph.optiedges
    assigned_edges = Vector{InterWorkerEdge}()
    for edge in parent_edges
        for node in edge.nodes
            if rgraph in traverse_parents(node) #TODO: Make this function faster
                push!(assigned_edges, edge)
            end
        end
    end
    return assigned_edges
end

function JuMP.all_variables(edge::E) where {E<:Union{InterWorkerEdge,RemoteEdgeRef}}
    con_refs = JuMP.all_constraints(edge)
    vars = vcat(extract_variables.(con_refs)...)
    return unique(vars)
end

function JuMP.dual(rgraph::RemoteOptiGraph, rcref::RemoteEdgeConstraintRef)
    redge = JuMP.owner_model(rcref)
    @assert rgraph == source_graph(redge)
    darray = rgraph.graph
    pedge = _convert_remote_to_proxy(rgraph, redge)

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        ledge = _convert_proxy_to_local(lgraph, pedge)
        cref = ConstraintRef(ledge, rcref.index, rcref.shape)
        JuMP.dual(lgraph, cref)
    end
    return fetch(f)
end

function JuMP.dual(rcref::RemoteEdgeConstraintRef)
    redge = JuMP.owner_model(rcref)
    rgraph = redge.remote_graph
    darray = rgraph.graph
    pcref = _convert_remote_to_proxy(rgraph, rcref)

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lcref = _convert_proxy_to_local(lgraph, pcref)
        JuMP.dual(lcref)
    end
    return fetch(f)
end

function JuMP.set_normalized_rhs(
    rcref::JuMP.ConstraintRef{InterWorkerEdge,MOI.ConstraintIndex{F,S}}, value::Number
) where {
    T,
    S<:Union{MOI.LessThan{T},MOI.GreaterThan{T},MOI.EqualTo{T}},
    F<:Union{MOI.ScalarAffineFunction{T},MOI.ScalarQuadraticFunction{T}},
}
    con = Plasmo.get_constraint(rcref)
    con.func.set = value
    return nothing
end

function JuMP.set_normalized_rhs(
    rcref::JuMP.ConstraintRef{R,MOI.ConstraintIndex{F,S}}, value::Number
) where {
    T,
    R<:Union{AbstractRemoteEdgeRef,AbstractRemoteNodeRef},
    S<:Union{MOI.LessThan{T},MOI.GreaterThan{T},MOI.EqualTo{T}},
    F<:Union{MOI.ScalarAffineFunction{T},MOI.ScalarQuadraticFunction{T}},
}
    rmodel = rcref.model
    rgraph = rmodel.remote_graph
    darray = rgraph.graph
    pcref = _convert_remote_to_proxy(rgraph, rcref)

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lcref = _convert_proxy_to_local(lgraph, pcref)
        JuMP.set_normalized_rhs(lcref, value)
    end
    return nothing
end

function JuMP.add_to_function_constant(
    rcref::JuMP.ConstraintRef{InterWorkerEdge,MOI.ConstraintIndex{F,S}}, value::Number
) where {
    T,
    S<:Union{MOI.LessThan{T},MOI.GreaterThan{T},MOI.EqualTo{T}},
    F<:Union{MOI.ScalarAffineFunction{T},MOI.ScalarQuadraticFunction{T}},
}
    con = Plasmo.get_constraint(rcref)
    con.func.set += value
    return nothing
end

function JuMP.add_to_function_constant(
    rcref::JuMP.ConstraintRef{R,MOI.ConstraintIndex{F,S}}, value::Number
) where {
    T,
    R<:Union{AbstractRemoteEdgeRef,AbstractRemoteNodeRef},
    S<:Union{MOI.LessThan{T},MOI.GreaterThan{T},MOI.EqualTo{T}},
    F<:Union{MOI.ScalarAffineFunction{T},MOI.ScalarQuadraticFunction{T}},
}
    rmodel = rcref.model
    rgraph = rmodel.remote_graph
    darray = rgraph.graph
    pcref = _convert_remote_to_proxy(rgraph, rcref)

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lcref = _convert_proxy_to_local(lgraph, pcref)
        JuMP.add_to_function_constant(lcref, value)
    end
    return nothing
end

function JuMP.delete(
    rmodel::R, rcref::JuMP.ConstraintRef
) where {R<:Union{AbstractRemoteEdgeRef,AbstractRemoteNodeRef}}
    if rcref.model != rmodel
        error(
            "The constraint reference you are trying to delete " *
            "does not belong to the remote node/edge",
        )
    end
    rgraph = rmodel.remote_graph
    darray = rgraph.graph
    pmodel = _convert_remote_to_proxy(rgraph, rcref)
    pcref = _convert_remote_to_proxy(rgraph, rcref)

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lmodel = _convert_proxy_to_local(lgraph, pmodel) # TODO: if obj_dict is added, make sure the name is deleted
        lcref = _convert_proxy_to_local(lgraph, pcref)
        JuMP.delete(lmodel, lcref)
    end
    return nothing
end

function JuMP.delete(redge::InterWorkerEdge, rcref::JuMP.ConstraintRef)
    if rcref.model != redge
        error(
            "The constraint reference you are trying to delete " *
            "does not belong to the InterWorkerEdge",
        )
    end
    delete!(redge.constraint_refs, rcref.index)
    delete!(redge.constraints, rcref)
    return nothing
end

# These functions are used by extending packages like PlasmoBenders to 
# set the needed type data
function edge_type(rgraph::RemoteOptiGraph)
    return InterWorkerEdge
end

function edge_type(rgraph::OptiGraph)
    return OptiEdge
end

# These functions allow for making sure dictionary keys recognize two RemoteNodeRefs
# instantiated at different times will still be equal to one another
function Base.isequal(redge1::RemoteEdgeRef, redge2::RemoteEdgeRef)
    return redge1.nodes == redge2.nodes && redge1.label == redge2.label
end

function Base.:(==)(redge1::RemoteEdgeRef, redge2::RemoteEdgeRef)
    return redge1.nodes == redge2.nodes && redge1.label == redge2.label
end

function Base.hash(redge::RemoteEdgeRef, h::UInt)
    return hash((redge.nodes, redge.label), h)
end

# Need to add the following
# TODO: Support these jump functions for vectors as well
# TODO: Probably move a lot of these jump extensions to another file

# Enable visualizing/printing a RemoteEdgeRef
function Base.string(redge::RemoteEdgeRef)
    return String(redge.label)
end
Base.print(io::IO, redge::RemoteEdgeRef) = Base.print(io, Base.string(redge))
Base.show(io::IO, redge::RemoteEdgeRef) = Base.print(io, redge)

# Enable visualizing/printing a RemoteOptiEdge
function Base.string(redge::RemoteOptiEdge)
    return String(redge.label)
end
Base.print(io::IO, redge::RemoteOptiEdge) = Base.print(io, Base.string(redge))
Base.show(io::IO, redge::RemoteOptiEdge) = Base.print(io, redge)

# Enable visualizing a remote constraint ref
function Base.string(rcref::RemoteOptiEdgeConstraintRef)
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

Base.print(io::IO, rcref::RemoteOptiEdgeConstraintRef) = Base.print(io, Base.string(rcref))
Base.show(io::IO, rcref::RemoteOptiEdgeConstraintRef) = Base.print(io, Base.string(rcref))

# return source graph (will be a RemoteOptiGraph)
function source_graph(redge::RemoteOptiEdge) return redge.remote_graph end
function source_graph(redge::RemoteEdgeRef) return redge.remote_graph end

# Extend Constraint Object call
function JuMP.constraint_object(
    con_ref::ConstraintRef{
        RemoteOptiEdge,
        MOI.ConstraintIndex{FuncType,SetType},
    },
) where {FuncType<:MOI.AbstractScalarFunction,SetType<:MOI.AbstractScalarSet}
    model = con_ref.model
    return model.constraints[con_ref]
end

# Add an edge for a set of RemoteNodeRefs
function add_edge(
    rgraph::RemoteOptiGraph,
    rnodes::RemoteNodeRef...;
    label = Symbol(rgraph.label, Symbol(".e"), length(rgraph.optiedges)+1)
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
        redge = RemoteOptiEdge(rgraph, OrderedSet(collect(rnodes)), OrderedDict{MOI.ConstraintIndex, Plasmo.RemoteOptiEdgeConstraintRef}(), OrderedDict{Plasmo.RemoteOptiEdgeConstraintRef, JuMP.AbstractConstraint}(), label)
        push!(rgraph.optiedges, redge)
        rgraph.edge_data.optiedge_map[Set(collect(rnodes))] = redge
    end
    return redge
end

# Check if an edge exists between the given nodes
function has_edge(rgraph::RemoteOptiGraph, rnodes::Set{RemoteNodeRef})
    if haskey(rgraph.edge_data.optiedge_map, rnodes)
        return true
    else
        return false
    end
end

function get_edge(rgraph::RemoteOptiGraph, rnodes::Set{RemoteNodeRef})
    return rgraph.edge_data.optiedge_map[rnodes]
end

function JuMP.is_valid(edge::RemoteOptiEdge, cref::ConstraintRef)
    return edge === JuMP.owner_model(cref)# && MOI.is_valid(graph_backend(edge), cref)
end

function JuMP.is_valid(edge::RemoteEdgeRef, cref::ConstraintRef)
    return edge === JuMP.owner_model(cref)# && MOI.is_valid(graph_backend(edge), cref)
end

function get_edge(cref::RemoteOptiEdgeConstraintRef)
    return JuMP.owner_model(cref)
end

function get_edge(cref::RemoteEdgeConstraintRef)
    return JuMP.owner_model(cref)
end

function get_constraint(rcref::RemoteOptiEdgeConstraintRef)
    redge = rcref.model
    @assert haskey(redge.constraints, rcref)
    return redge.constraints[rcref]
end

function next_constraint_index(
    redge::RemoteOptiEdge, ::Type{F}, ::Type{S}
)::MOI.ConstraintIndex{F,S} where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    source_data = source_graph(redge).edge_data
    if !haskey(source_data.last_constraint_index, redge)
        source_data.last_constraint_index[redge] = 0
    end
    source_data.last_constraint_index[redge] += 1
    return MOI.ConstraintIndex{F,S}(source_data.last_constraint_index[redge])
end

# build the constraint reference for an edge
function _build_constraint_ref(redge::RemoteOptiEdge, con::JuMP.AbstractConstraint)
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

"""
    Plasmo.incident_edges(rgraph::RemoteOptiGraph)

Get the set of incident edges to a given `rgraph`. This requires the `rgraph` to have 
a parent graph, which is what will be search to get the incident edges
"""
function incident_edges(rgraph::RemoteOptiGraph)
    !(isnothing(rgraph.parent_graph)) || error("Given graph does not have parent graph")
    parent_graph = rgraph.parent_graph
    parent_edges = parent_graph.optiedges
    assigned_edges = Vector{RemoteOptiEdge}()
    for edge in parent_edges
        for node in edge.nodes
            if rgraph in containing_optigraphs(node) #TODO: Make this function faster
                push!(assigned_edges, edge)
            end
        end
    end
    return assigned_edges
end

function JuMP.all_constraints(redge::RemoteOptiEdge)
    return collect(keys(redge.constraints))
end

function JuMP.dual(rgraph::RemoteOptiGraph, rcref::RemoteEdgeConstraintRef)
    redge = JuMP.owner_model(rcref) #TODO: Make sure the redge is owned by the rgraph
    f = @spawnat rgraph.worker begin
        lgraph = local_graph(rgraph)
        ledge = _convert_remote_to_local(rgraph, redge)
        cref = ConstraintRef(ledge, rcref.index, rcref.shape)
        JuMP.dual(lgraph, cref)
    end
    return fetch(f)
end

function JuMP.dual(rcref::RemoteEdgeConstraintRef)
    redge = JuMP.owner_model(rcref)
    rgraph = redge.remote_graph
    f = @spawnat rgraph.worker begin
        ledge = _convert_remote_to_local(rgraph, redge)
        cref = ConstraintRef(ledge, rcref.index, rcref.shape)
        JuMP.dual(cref)
    end
    return fetch(f)
end

function JuMP.set_normalized_rhs(
    rcref::JuMP.ConstraintRef{RemoteOptiEdge, MOI.ConstraintIndex{F,S}}, 
    value::Number
)  where {
    T,
    S<:Union{MOI.LessThan{T},MOI.GreaterThan{T},MOI.EqualTo{T}},
    F<:Union{MOI.ScalarAffineFunction{T},MOI.ScalarQuadraticFunction{T}},
}
    con = Plasmo.get_constraint(rcref)
    con.func.set = value
    return nothing
end

function JuMP.set_normalized_rhs(
    rcref::JuMP.ConstraintRef{R, MOI.ConstraintIndex{F,S}}, 
    value::Number
)  where {
    T,
    R<:Union{AbstractRemoteEdgeRef, AbstractRemoteNodeRef},
    S<:Union{MOI.LessThan{T},MOI.GreaterThan{T},MOI.EqualTo{T}},
    F<:Union{MOI.ScalarAffineFunction{T},MOI.ScalarQuadraticFunction{T}},
}
    rmodel = rcref.model
    rgraph = rmodel.remote_graph
    f = @spawnat rgraph.worker begin
        lcref = _convert_remote_to_local(rgraph, rcref)
        JuMP.set_normalized_rhs(lcref, value)
    end
    return nothing
end

function JuMP.add_to_function_constant(
    rcref::JuMP.ConstraintRef{RemoteOptiEdge, MOI.ConstraintIndex{F,S}}, 
    value::Number
)  where {
    T,
    S<:Union{MOI.LessThan{T},MOI.GreaterThan{T},MOI.EqualTo{T}},
    F<:Union{MOI.ScalarAffineFunction{T},MOI.ScalarQuadraticFunction{T}},
}
    con = Plasmo.get_constraint(rcref)
    con.func.set += value
    return nothing
end

function JuMP.add_to_function_constant(
    rcref::JuMP.ConstraintRef{R, MOI.ConstraintIndex{F,S}}, 
    value::Number
)  where {
    T,
    R<:Union{AbstractRemoteEdgeRef, AbstractRemoteNodeRef},
    S<:Union{MOI.LessThan{T},MOI.GreaterThan{T},MOI.EqualTo{T}},
    F<:Union{MOI.ScalarAffineFunction{T},MOI.ScalarQuadraticFunction{T}},
}
    rmodel = rcref.model
    rgraph = rmodel.remote_graph
    f = @spawnat rgraph.worker begin
        lcref = _convert_remote_to_local(rgraph, rcref)
        JuMP.add_to_function_constant(lcref, value)
    end
    return nothing
end

function JuMP.set_normalized_coefficient(
    rcref::JuMP.ConstraintRef{RemoteOptiEdge, MOI.ConstraintIndex{F,S}},
    var::RemoteVariableRef,
    value::Number
)  where {
    T,
    S<:Union{MOI.LessThan{T},MOI.GreaterThan{T},MOI.EqualTo{T}},
    F<:Union{MOI.ScalarAffineFunction{T},MOI.ScalarQuadraticFunction{T}},
}
    con = Plasmo.get_constraint(rcref)
    @assert haskey(con.func.terms, var)
    con.func.terms[var] = value
    return nothing
end

function JuMP.set_normalized_coefficient(
    rcref::JuMP.ConstraintRef{R, MOI.ConstraintIndex{F,S}}, 
    var::RemoteVariableRef,
    value::Number
)  where {
    T,
    R<:Union{AbstractRemoteEdgeRef, AbstractRemoteNodeRef},
    S<:Union{MOI.LessThan{T},MOI.GreaterThan{T},MOI.EqualTo{T}},
    F<:Union{MOI.ScalarAffineFunction{T},MOI.ScalarQuadraticFunction{T}},
}
    rmodel = rcref.model
    rgraph = rmodel.remote_graph
    f =@spawnat rgraph.worker begin
        lcref = _convert_remote_to_local(rgraph, rcref)
        lvar = _convert_remote_to_local(rgraph, var)
        JuMP.set_normalized_coefficient(lcref, lvar, value)
    end
    return nothing
end

function JuMP.normalized_coefficient(
    rcref::JuMP.ConstraintRef{RemoteOptiEdge, MOI.ConstraintIndex{F,S}},
    var::RemoteVariableRef
)  where {
    T,
    S<:Union{MOI.LessThan{T},MOI.GreaterThan{T},MOI.EqualTo{T}},
    F<:Union{MOI.ScalarAffineFunction{T},MOI.ScalarQuadraticFunction{T}},
}
    con = Plasmo.get_constraint(rcref)
    @assert haskey(con.func.terms, var)
    return con.func.terms[var]
end

function JuMP.normalized_coefficient(
    rcref::JuMP.ConstraintRef{R, MOI.ConstraintIndex{F,S}}, 
    var::RemoteVariableRef
)  where {
    T,
    R<:Union{AbstractRemoteEdgeRef, AbstractRemoteNodeRef},
    S<:Union{MOI.LessThan{T},MOI.GreaterThan{T},MOI.EqualTo{T}},
    F<:Union{MOI.ScalarAffineFunction{T},MOI.ScalarQuadraticFunction{T}},
}
    rmodel = rcref.model
    rgraph = rmodel.remote_graph
    f =@spawnat rgraph.worker begin
        lcref = _convert_remote_to_local(rgraph, rcref)
        lvar = _convert_remote_to_local(rgraph, var)
        JuMP.normalized_coefficient(lcref, lvar)
    end
    return fetch(f)
end

function JuMP.delete(rmodel::R, rcref::JuMP.ConstraintRef) where {R<:Union{AbstractRemoteEdgeRef, AbstractRemoteNodeRef}}
    if rcref.model != rmodel
        error("The constraint reference you are trying to delete " * 
            "does not belong to the remote node/edge"
        ) 
    end
    rgraph = rmodel.remote_graph
    f = @spawnat rgraph.worker begin
        lmodel = _convert_remote_to_local(rgraph, rmodel) # TODO: if obj_dict is added, make sure the name is deleted
        lcref = _convert_remote_to_local(rgraph, rcref)
        JuMP.delete(lmodel, lcref)
    end
    return nothing
end

function JuMP.delete(redge::RemoteOptiEdge, rcref::JuMP.ConstraintRef)
    if rcref.model != redge
        error("The constraint reference you are trying to delete " * 
            "does not belong to the RemoteOptiEdge"
        ) 
    end
    delete!(redge.constraint_refs, rcref.index)
    delete!(redge.constraints, rcref)
    return nothing
end


# These functions are used by extending packages like PlasmoBenders to 
# set the needed type data
function edge_type(rgraph::RemoteOptiGraph)
    return RemoteOptiEdge
end

function edge_type(rgraph::OptiGraph)
    return OptiEdge
end

# Need to add the following
# JuMP.delete (for variables and node constraints and edge constraints)
# TODO: Support these jump functions for vectors as well
# TODO: Probably move a lot of these jump extensions to another file

# for variables: delete(rnode, rvar)
# for constraints: delete(redgeref, rcon)
# for constraints: delete(roptiedge, rcon)
# for constraints: delete(rnode, rcon)
function Base.string(redge::RemoteEdgeRef)
    return String(redge.label)
end
Base.print(io::IO, redge::RemoteEdgeRef) = Base.print(io, Base.string(redge))
Base.show(io::IO, redge::RemoteEdgeRef) = Base.print(io, redge)

function Base.string(redge::RemoteOptiEdge)
    return String(redge.label)
end
Base.print(io::IO, redge::RemoteOptiEdge) = Base.print(io, Base.string(redge))
Base.show(io::IO, redge::RemoteOptiEdge) = Base.print(io, redge)

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

function source_graph(redge::RemoteOptiEdge) return redge.remote_graph end
function source_graph(redge::RemoteEdgeRef) return redge.remote_graph end

function JuMP.constraint_object(rcref::RemoteOptiEdgeConstraintRef)
    redge = JuMP.owner_model(rcref)
    return redge.constriants[rcref]
end

function add_edge(
    rgraph::RemoteOptiGraph,
    rnodes::RemoteNodeRef...;
    label = Symbol(rgraph.label, Symbol(".e"), length(rgraph.optiedges)+1)
)
    if has_edge(rgraph, Set(rnodes))
        redge = get_edge(rgraph, Set(rnodes))
    else
        subgraphs = [rgraph; all_subgraphs(rgraph)]
        if !(all(x -> x.remote_graph in subgraphs, rnodes))
            error("Remote Nodes do not belong to the remote graph or its subgrpahs")
        end

        redge = RemoteOptiEdge(rgraph, OrderedSet(collect(rnodes)), OrderedDict{MOI.ConstraintIndex, Plasmo.RemoteOptiEdgeConstraintRef}(), OrderedDict{Plasmo.RemoteOptiEdgeConstraintRef, JuMP.AbstractConstraint}(), label)
        push!(rgraph.optiedges, redge)
        rgraph.edge_data.optiedge_map[Set(collect(rnodes))] = redge
    end
    return redge
end

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

function incident_edges(rgraph::RemoteOptiGraph)
    !(isnothing(rgraph.parent_graph)) || error("Given graph does not have parent graph")
    parent_graph = rgraph.parent_graph
    parent_edges = parent_graph.optiedges
    assigned_edges = Vector{RemoteOptiEdge}()
    for edge in parent_edges
        for node in edge.nodes
            if rgraph in containing_optigraphs(node) #TODO: Make this function faster
                push!(edge, assigned_edges)
            end
        end
    end
    return assigned_edges
end

function JuMP.all_constraints(redge::RemoteOptiEdge)
    return collect(values(redge.constraints))
end

function JuMP.dual(rgraph::RemoteOptiGraph, rcref::RemoteEdgeConstraintRef)
    redge = JuMP.owner_model(rcref) #TODO: Make sure the redge is owned by the rgraph
    f = @spawnat rgraph.worker begin
        lgraph = local_graph(rgraph)
        ledge = remote_edge_to_local(rgraph, redge)
        cref = ConstraintRef(ledge, rcref.index, rcref.shape)
        JuMP.dual(lgraph, cref)
    end
    return fetch(f)
end

function JuMP.dual(rcref::RemoteEdgeConstraintRef)
    redge = JuMP.owner_model(rcref)
    rgraph = redge.remote_graph
    f = @spawnat rgraph.worker begin
        ledge = remote_edge_to_local(rgraph, redge)
        cref = ConstraintRef(ledge, rcref.index, rcref.shape)
        JuMP.dual(cref)
    end
    return fetch(f)
end
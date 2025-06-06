# A remote graph tracks its worker and a DistributedArray as a persistent reference to the graph on the worker
# The remote graph can also have a subset of other, nested remote graphs that are distributed on other workers

abstract type AbstractRemoteOptiEdge <: JuMP.AbstractModel end
abstract type AbstractRemoteEdgeRef <: JuMP.AbstractModel end
abstract type AbstractRemoteNodeRef <: JuMP.AbstractModel end

const RemoteOptiEdgeConstraintRef = JuMP.ConstraintRef{
    <:AbstractRemoteOptiEdge,MOI.ConstraintIndex{FT,ST},<:JuMP.AbstractShape
} where {FT<:MOI.AbstractFunction,ST<:MOI.AbstractSet}

const RemoteEdgeConstraintRef = JuMP.ConstraintRef{
    <:AbstractRemoteEdgeRef,MOI.ConstraintIndex{FT,ST},<:JuMP.AbstractShape
} where {FT<:MOI.AbstractFunction,ST<:MOI.AbstractSet}

const RemoteNodeConstraintRef = JuMP.ConstraintRef{
    <:AbstractRemoteNodeRef,MOI.ConstraintIndex{FT,ST},<:JuMP.AbstractShape
} where {FT<:MOI.AbstractFunction,ST<:MOI.AbstractSet}

const RemoteConstraintRef = JuMP.ConstraintRef{
    <:R,MOI.ConstraintIndex{FT,ST},<:JuMP.AbstractShape
} where {R<:Union{AbstractRemoteEdgeRef,AbstractRemoteNodeRef,AbstractRemoteOptiEdge},FT<:MOI.AbstractFunction,ST<:AbstractSet}
# or should this be it's own mutable struct that is an abstractlinkconstraint

mutable struct RemoteEdgeData #TODO: merge the `constraints` attribute of the RemoteEdgeRef with this struct; I think the crefs should live on the graph, not on the edge structure
    optiedge_map::OrderedDict{Set{<:AbstractRemoteNodeRef}, AbstractRemoteOptiEdge}
    last_constraint_index::OrderedDict{AbstractRemoteOptiEdge, Int64}
end

mutable struct RemoteOptiGraph <: AbstractOptiGraph
    worker::Int
    graph::DArray{OptiGraph, 1, Vector{OptiGraph}} # I think this should only be allowed to be a length one vector. If it is anymore, than the user should just create a new RemoteOptiGraph object
    parent_graph::Union{Nothing, RemoteOptiGraph}
    subgraphs::Vector{RemoteOptiGraph} # These are nested remote optigraph objects; all remote optigraphs live on the main worker, but they contain a distributed optigraph that does not have to live on the main worker
    optiedges::Vector{<:AbstractRemoteOptiEdge}
    edge_data::RemoteEdgeData
    label::Symbol
    ext::Dict{Symbol, Any}
end #TODO: Maybe add an obj_dict and node_obj_dict for saving and referencing remotenoderefs or RemoteVariableRefs; add an element_data section; add an ext option too

struct RemoteNodeRef <: AbstractRemoteNodeRef
    remote_graph::Plasmo.RemoteOptiGraph
    node_idx::NodeIndex
    node_label::Base.RefValue{Symbol}
end

struct RemoteVariableRef <: JuMP.AbstractVariableRef
    node::Plasmo.RemoteNodeRef
    index::MOI.VariableIndex
    name::Symbol
end

struct RemoteEdgeRef <: AbstractRemoteEdgeRef
    remote_graph::Plasmo.RemoteOptiGraph #TODO: Decide if this should be `remote_graph` or just `graph`
    nodes::OrderedSet{Plasmo.RemoteNodeRef}
    label::Symbol
end

struct RemoteOptiEdge <: AbstractRemoteOptiEdge
    remote_graph::Plasmo.RemoteOptiGraph #TODO: Decide if this should be `remote_graph` or just `graph`
    nodes::OrderedSet{Plasmo.RemoteNodeRef}
    constraint_refs::OrderedDict{MOI.ConstraintIndex, Plasmo.RemoteOptiEdgeConstraintRef} #TODO: probably move this to the graph rather than being an attribute of the edge ref; see note on EdgeData struct
    constraints::OrderedDict{Plasmo.RemoteOptiEdgeConstraintRef, JuMP.AbstractConstraint}
    label::Symbol
end

const RemoteAffExpr = JuMP.GenericAffExpr{
    Float64, RemoteVariableRef
}

const RemoteOptiObject = Union{
    RemoteNodeRef, RemoteEdgeRef, RemoteOptiGraph
}

function RemoteOptiGraph(; name::Symbol=Symbol(:rg, gensym()), worker::Int=1)
    if !(worker in procs())
        error("The provided worker $worker is not in existing workers: $(procs())")
    end
    darray = distribute([OptiGraph(name=name)], procs=[worker])
    rgraph = RemoteOptiGraph(
        worker, 
        darray, 
        nothing,
        Vector{RemoteOptiGraph}(), 
        Vector{Plasmo.RemoteOptiEdge}(), 
        RemoteEdgeData(),
        name, #not sure yet whether the remote and local should have the same name, but doing that for now
        Dict{Symbol, Any}()
    )
    return rgraph
end

function RemoteEdgeData()
    edge_data = RemoteEdgeData(
        OrderedDict{Set{RemoteNodeRef},RemoteEdgeRef}(), 
        OrderedDict{RemoteEdgeRef, Int64}(), 
    )
    return edge_data
end

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

"""
    RemoteEdgeData

A data structure for saving mappings relating to RemoteOptiEdges. Includes an `optiedge_map`
which maps from sets of sets of RemtoeNodeRefs to an AbstractRemoteOptiEdge object. Also 
includes a `last_constraint_index` used in defining new constraint data
"""
mutable struct RemoteEdgeData #TODO: merge the `constraints` attribute of the RemoteEdgeRef with this struct; I think the crefs should live on the graph, not on the edge structure
    optiedge_map::OrderedDict{Set{<:AbstractRemoteNodeRef}, AbstractRemoteOptiEdge}
    last_constraint_index::OrderedDict{AbstractRemoteOptiEdge, Int64}
end

"""
    RemoteOptiGraph

A core modeling object for working with Plasmo.jl in a distributed manner. The RemoteOptiGraph 
object is stored on the main worker but contains an attribute `graph` that is stored on a
remote worker `worker`. RemoteOptiGraphs can be nested within other RemoteOptiGraphs similar to
optigraphs stored in the shared memory. `RemoteNodeRefs`, `RemoteEdgeRefs` and `RemoteVariableRefs`
are light references to objects stored on the remote workers. 

The RemoteOptiGraph acts a "wrapper" for an OptiGraph distributed to a remote worker.
"""
mutable struct RemoteOptiGraph <: AbstractOptiGraph
    # worker assignment where the `graph` object will lieve
    worker::Int 
    # OptiGraph stored on worker
    graph::DArray{OptiGraph, 1, Vector{OptiGraph}} # I think this should only be allowed to be a length one vector. If it is anymore, than the user should just create a new RemoteOptiGraph object
    # parent graph pointer
    parent_graph::Union{Nothing, RemoteOptiGraph}
    # Vector of nested RemoteOptiGraphs; these can be stored on different workers
    subgraphs::Vector{RemoteOptiGraph} # These are nested remote optigraph objects; all remote optigraphs live on the main worker, but they contain a distributed optigraph that does not have to live on the main worker
    # Set of edges and data for them
    optiedges::Vector{<:AbstractRemoteOptiEdge}
    edge_data::RemoteEdgeData
    label::Symbol
    ext::Dict{Symbol, Any}
end #TODO: Maybe add an obj_dict and node_obj_dict for saving and referencing remotenoderefs or RemoteVariableRefs; this would allow for registering expression names to a remote optigraph, which is currently not done

"""
    RemoteNodeRef

A "lightweight" reference to a node stored remotely on the OptiGraph stored on a RemoteOptiGraph.
"""
struct RemoteNodeRef <: AbstractRemoteNodeRef
    # idx and label match the local node's idx and label
    remote_graph::Plasmo.RemoteOptiGraph
    node_idx::NodeIndex #
    node_label::Base.RefValue{Symbol}
end

"""
    RemoteVariableRef

A "lightweight" reference to a variable stored remotely on the OptiGraph stored on a RemoteOptiGraph.
"""
struct RemoteVariableRef <: JuMP.AbstractVariableRef
    node::Plasmo.RemoteNodeRef
    index::MOI.VariableIndex
    name::Symbol
end

"""
    RemoteEdgeRef

A "lightweight" reference to an edge stored remotely on the OptiGraph stored on a RemoteOptiGraph.
"""
struct RemoteEdgeRef <: AbstractRemoteEdgeRef
    remote_graph::Plasmo.RemoteOptiGraph #TODO: Decide if this should be `remote_graph` or just `graph`
    nodes::OrderedSet{Plasmo.RemoteNodeRef}
    label::Symbol
end

"""
    RemoteOptiEdge

An OptiEdge for RemoteOptiGraphs. These edges only connect between a RemoteOptiGraph's local 
optigraph and/or its sub-RemoteOptiGraphs. These edges are intended for use by decomposition approaches
"""
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
    RemoteNodeRef, RemoteEdgeRef, RemoteOptiGraph, RemoteOptiEdge
}

"""
    RemoteOptiGraph(; name::Symbol, worker::Int = 1)

A constructor function for building a RemoteOptiGraph. The actual optigraph object of the
RemoteOptiGraph object is stored on the worker `worker`. A name can be passed as a keyword argument
"""
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

struct RemoteVariableArrayRef
    node::Plasmo.RemoteNodeRef
    name::Symbol
    axes::Tuple
end
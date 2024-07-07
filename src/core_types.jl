abstract type AbstractOptiGraph <: JuMP.AbstractModel end

abstract type AbstractOptiNode <: JuMP.AbstractModel end

abstract type AbstractOptiEdge <: JuMP.AbstractModel end

struct NodeIndex
    value::Symbol
end

# NOTE: a node or edge could technically have their `source_graph` 
# changed using `apply_partition!`. that is why we use a RefValue here.
# NOTE: We parameterize nodes and edges on the graph type itself. This may instead
# become a special type that denotes whether we have a standard optigraph, or a 
# distributed memory optigraph in the future.

"""
    OptiNode{GT<:AbstractOptiGraph} <: AbstractOptiNode

A data structure meant to encapsulate variables, constraints, an objective function, and 
other model data. An optinode is "lightweight" in the sense that it does not directly 
contain model data, but instead acts as an interface that maps to a backend where 
the model data is stored. This avoids the need to generate memory overhead through 
container structures in cases when a node contains very little model data.
"""
struct OptiNode{GT<:AbstractOptiGraph} <: AbstractOptiNode
    source_graph::Base.RefValue{<:GT}
    idx::NodeIndex
    label::Base.RefValue{Symbol}
end

"""
    OptiEdge{GT<:AbstractOptiGraph} <: AbstractOptiEdge

A data structure meant to encapsulate linking constraints other model data. An optiedge 
is "lightweight" in the sense that it does not directly contain model data, but instead acts
as an interface that maps to a backend where the model data is stored. This avoids the need 
to generate memory overhead through container structures in cases when a node contains very 
little model data.
"""
struct OptiEdge{GT<:AbstractOptiGraph} <: AbstractOptiEdge
    source_graph::Base.RefValue{<:GT}
    label::Symbol
    nodes::OrderedSet{OptiNode}
end

"""
    OptiGraph

The core modeling object of Plasmo.jl. An optigraph represents an optimization model as 
a set of `OptiNode` and `OptiEdge` objects.
"""
mutable struct OptiGraph <: AbstractOptiGraph
    label::Symbol

    optinodes::OrderedSet{OptiNode{OptiGraph}}
    optiedges::OrderedSet{OptiEdge{OptiGraph}}
    subgraphs::OrderedSet{OptiGraph}
    optiedge_map::OrderedDict{Set{OptiNode{OptiGraph}},OptiEdge{OptiGraph}}

    # subgraphs keep a reference to their parent
    parent_graph::Union{Nothing,OptiGraph}

    # track node membership in other graphs; nodes use this to query different backends
    node_to_graphs::OrderedDict{OptiNode{OptiGraph},Vector{OptiGraph}}
    edge_to_graphs::OrderedDict{OptiEdge{OptiGraph},Vector{OptiGraph}}

    # special case where nodes are optimized directly
    node_graphs::OrderedDict{OptiNode{OptiGraph},OptiGraph}

    # intermediate backend that maps graph elements to the actual model
    backend::Union{Nothing,MOI.ModelLike}

    node_obj_dict::OrderedDict{Tuple{OptiNode{OptiGraph},Symbol},Any}
    edge_obj_dict::OrderedDict{Tuple{OptiEdge{OptiGraph},Symbol},Any}
    obj_dict::Dict{Symbol,Any}
    ext::Dict{Symbol,Any}

    bridge_types::Set{Any}
    is_model_dirty::Bool
end

const OptiElement = Union{OptiNode{<:AbstractOptiGraph},OptiEdge{<:AbstractOptiGraph}}

const OptiObject = Union{
    OptiNode{<:AbstractOptiGraph},OptiEdge{<:AbstractOptiGraph},OptiGraph
}

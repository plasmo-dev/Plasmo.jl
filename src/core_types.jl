#  Copyright 2021, Jordan Jalving, Yankai Cao, Victor Zavala, and contributors
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at https://mozilla.org/MPL/2.0/.

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

A data structure meant to encapsulate linking constraints and other model data. An optiedge 
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

const OptiElement = Union{OptiNode{<:AbstractOptiGraph},OptiEdge{<:AbstractOptiGraph}}

struct ElementData{GT<:AbstractOptiGraph}
    # track node membership in other graphs; nodes use this to query different backends
    node_to_graphs::OrderedDict{OptiNode{GT},Vector{GT}}
    edge_to_graphs::OrderedDict{OptiEdge{GT},Vector{GT}}

    # special case where nodes are optimized directly
    node_graphs::OrderedDict{OptiNode{GT},GT}

    # node and edge object dictionaries
    node_obj_dict::OrderedDict{Tuple{OptiNode{GT},Symbol},Any}
    edge_obj_dict::OrderedDict{Tuple{OptiEdge{GT},Symbol},Any}

    # track variable indices 
    last_variable_index::OrderedDict{OptiNode,Int}

    # track constraint indices
    last_constraint_index::OrderedDict{OptiElement,Int}
end
function ElementData(GT::Type{<:AbstractOptiGraph})
    return ElementData{GT}(
        OrderedDict{OptiNode{GT},Vector{GT}}(),
        OrderedDict{OptiEdge{GT},Vector{GT}}(),
        OrderedDict{OptiNode{GT},GT}(),
        OrderedDict{Tuple{OptiNode{GT},Symbol},Any}(),
        OrderedDict{Tuple{OptiEdge{GT},Symbol},Any}(),
        OrderedDict{OptiNode{GT},Int}(),
        OrderedDict{OptiElement,Int}(),
    )
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

    # all mappings related to graph elements
    element_data::ElementData{OptiGraph}

    # intermediate backend that maps graph elements to the actual model
    backend::Union{Nothing,MOI.ModelLike}
    obj_dict::Dict{Symbol,Any}
    ext::Dict{Symbol,Any}

    bridge_types::Set{Any}
    is_model_dirty::Bool
end

const OptiObject = Union{
    OptiNode{<:AbstractOptiGraph},OptiEdge{<:AbstractOptiGraph},OptiGraph
}

const NodeConstraintRef = JuMP.ConstraintRef{
    OptiNode{GT},MOI.ConstraintIndex{FT,ST},<:JuMP.AbstractShape
} where {GT<:AbstractOptiGraph,FT<:MOI.AbstractFunction,ST<:MOI.AbstractSet}

const EdgeConstraintRef = JuMP.ConstraintRef{
    OptiEdge{GT},MOI.ConstraintIndex{FT,ST},<:JuMP.AbstractShape
} where {GT<:AbstractOptiGraph,FT<:MOI.AbstractFunction,ST<:MOI.AbstractSet}

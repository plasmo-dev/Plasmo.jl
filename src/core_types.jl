abstract type AbstractOptiGraph <: JuMP.AbstractModel end

abstract type AbstractNode <: JuMP.AbstractModel end

abstract type AbstractEdge <: JuMP.AbstractModel end

mutable struct OptiGraph{NT <: AbstractNode, ET <: AbstractEdge} <: AbstractOptiGraph
    label::Symbol

    optinodes::OrderedSet{NT}   
    optiedges::OrderedSet{ET}
    subgraphs::OrderedSet{OptiGraph}
    optiedge_map::OrderedDict{Set{NT},ET}

    # subgraphs keep a reference to their parent
    parent_graph::Union{Nothing,OptiGraph}

    # track node membership in other graphs; nodes use this to query different backends
    node_to_graphs::OrderedDict{NT,Vector{OptiGraph}}
    edge_to_graphs::OrderedDict{ET,Vector{OptiGraph}}

    # special case where nodes are optimized directly
    node_graphs::OrderedDict{NT,OptiGraph}

    # intermediate backend that maps graph elements to the actual model
    backend::Union{Nothing,MOI.ModelLike}

    node_obj_dict::OrderedDict{Tuple{NT,Symbol},Any}
    edge_obj_dict::OrderedDict{Tuple{ET,Symbol},Any}
    obj_dict::Dict{Symbol,Any}
    ext::Dict{Symbol,Any}

    bridge_types::Set{Any}
    is_model_dirty::Bool
end

struct NodeIndex
    value::Symbol
end

# NOTE: a node or edge could technically have their `source_graph` 
# changed using `apply_partition!`. that is why we use a RefValue here.

struct OptiNode <: AbstractNode
    source_graph::Base.RefValue{<:OptiGraph}
    idx::NodeIndex
    label::Symbol
end

struct OptiEdge <: AbstractEdge
    source_graph::Base.RefValue{<:OptiGraph}
    label::Symbol
    nodes::OrderedSet{OptiNode}
end

const OptiElement = Union{OptiNode,OptiEdge}

const OptiObject = Union{OptiNode, OptiEdge, OptiGraph}
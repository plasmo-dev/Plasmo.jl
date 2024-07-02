abstract type AbstractOptiGraph <: JuMP.AbstractModel end

abstract type AbstractNode <: JuMP.AbstractModel end

abstract type AbstractEdge <: JuMP.AbstractModel end

struct NodeIndex
    value::Symbol
end

# NOTE: a node or edge could technically have their `source_graph` 
# changed using `apply_partition!`. that is why we use a RefValue here.
# NOTE: We parameterize nodes and edges on the graph type itself. This may instead
# become a special type that denotes whether we have a standard optigraph, or a 
# distributed memory optigraph in the future.
struct OptiNode{GT<:AbstractOptiGraph} <: AbstractNode
    source_graph::Base.RefValue{<:GT}
    idx::NodeIndex
    label::Symbol
end

struct OptiEdge{GT<:AbstractOptiGraph} <: AbstractEdge
    source_graph::Base.RefValue{<:GT}
    label::Symbol
    nodes::OrderedSet{OptiNode}
end

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
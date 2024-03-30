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

    # it is possible nodes and edges may use a parent graph as their model backend
    # this is the case if constructing an optigraph from subgraphs
    optimizer_graph::Union{Nothing,OptiGraph}

    # track node membership in other graphs; nodes use this to query different backends
    node_to_graphs::OrderedDict{NT,Vector{OptiGraph}}
    edge_to_graphs::OrderedDict{ET,Vector{OptiGraph}}

    # intermediate moi backend that maps graph elements to an MOI model
    backend::Union{Nothing,MOI.ModelLike}

    node_obj_dict::OrderedDict{Tuple{NT,Symbol},Any} # object dictionary for nodes
    edge_obj_dict::OrderedDict{Tuple{ET,Symbol},Any} # object dictionary for edges
    obj_dict::Dict{Symbol,Any}
    ext::Dict{Symbol,Any}

    bridge_types::Set{Any}
    is_model_dirty::Bool
end

struct NodeIndex
    value::Int
end

struct OptiNode <: AbstractNode
    source_graph::OptiGraph
    idx::NodeIndex
    label::Symbol
end

struct OptiEdge <: AbstractEdge
    source_graph::OptiGraph
    label::Symbol
    nodes::OrderedSet{OptiNode}
end

const OptiElement = Union{OptiNode,OptiEdge}

struct NodeVariableRef <: JuMP.AbstractVariableRef
    node::OptiNode
    index::MOI.VariableIndex
end

    #Constructor
    # function OptiGraph(;
    #     name::Symbol=Symbol(:g,gensym())
    # )
    #     optigraph = new{NT,ET}()
    #     optigraph.optinodes = OrderedSet{NT}()
    #     optigraph.optiedges = OrderedSet{ET}()
    #     optigraph.subgraphs = OrderedSet{OptiGraph}()
    #     optigraph.optiedge_map = OrderedDict{Set{NT},ET}()
    #     optigraph.parent_graph = nothing
    #     optigraph.optimizer_graph = optigraph

    #     optigraph.node_to_graphs = OrderedDict{NT,Vector{OptiGraph}}()
    #     optigraph.node_obj_dict = OrderedDict{Tuple{NT,Symbol},Any}()
    #     optigraph.edge_to_graphs = OrderedDict{ET,Vector{OptiGraph}}()
    #     optigraph.edge_obj_dict = OrderedDict{Tuple{ET,Symbol},Any}()

    #     optigraph.backend = GraphMOIBackend(optigraph)
    #     optigraph.obj_dict = Dict{Symbol,Any}()
    #     optigraph.ext = Dict{Symbol,Any}()
    #     optigraph.label = name

    #     optigraph.bridge_types = Set{Any}()
    #     optigraph.is_model_dirty = false 
    #     return optigraph
    # end
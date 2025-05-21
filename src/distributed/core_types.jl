# A remote graph tracks its worker and a DistributedArray as a persistent reference to the graph on the worker

abstract type AbstractRemoteEdgeRef <: JuMP.AbstractModel end

const RemoteEdgeConstraintRef = JuMP.ConstraintRef{
    <:AbstractRemoteEdgeRef,MOI.ConstraintIndex{FT,ST},<:JuMP.AbstractShape
} where {FT<:MOI.AbstractFunction,ST<:MOI.AbstractSet}

mutable struct RemoteOptiGraph <: AbstractOptiGraph
    worker::Int
    graph::DArray{OptiGraph, 1, Vector{OptiGraph}} # I think this should only be allowed to be a length one vector. If it is anymore, than the user should just create a new RemoteOptiGraph object
    subgraphs::Union{Nothing, DArray{RemoteOptiGraph, 1, Vector{RemoteOptiGraph}}} # These are nested RemoteOptiGraph objects
    optiedges::Vector{<:AbstractRemoteEdgeRef}
end

struct RemoteNodeRef <: JuMP.AbstractModel
    remote_graph::Plasmo.RemoteOptiGraph
    node_idx::NodeIndex
    node_label::Base.RefValue{Symbol}
end

struct RemoteVarRef <: JuMP.AbstractVariableRef
    node::Plasmo.RemoteNodeRef
    index::MOI.VariableIndex
    name::Symbol
end

struct RemoteEdgeRef <: AbstractRemoteEdgeRef
    source_graph::Plasmo.RemoteOptiGraph
    nodes::OrderedSet{Plasmo.RemoteNodeRef}
    constraints::OrderedSet{Plasmo.RemoteEdgeConstraintRef}
end

function RemoteOptiGraph(; name::Symbol=:remote, worker::Int=1)
    if !(worker in workers())
        error("The provided worker $worker is not in existing workers: $(workers())")
    end
    darray = distribute([OptiGraph(name=name)], procs=[worker])
    return RemoteOptiGraph(worker, darray, nothing, Vector{Plasmo.RemoteEdgeRef}())
end

function local_graph(rgraph::RemoteOptiGraph)
    return localpart(rgraph.graph)[1]
end

function print_local_graph(rgraph::RemoteOptiGraph)
    @spawnat rgraph.worker println(localpart(rgraph.graph)[1])
    return nothing
end

function get_local_graph(rgraph::RemoteOptiGraph)
    f = @spawnat rgraph.worker localpart(rgraph.graph)[1]
    return fetch(f)
end

function add_node(rgraph::RemoteOptiGraph)
    f = @spawnat rgraph.worker begin
        n = add_node(localpart(rgraph.graph)[1])
        (n.idx, n.label)
    end
    node_tuple = fetch(f)
    return RemoteNodeRef(rgraph, node_tuple[1], node_tuple[2])
end

function add_node(rgraph::RemoteOptiGraph, sym::Symbol) # TODO: Rethink whether this can be merged with previous function; the problem is that I want to keep the kwarg default of add_node(graph::OptiGraph), which also calls length(graph.optinodes); trying to use that same default argument in the add_node(rgraph::RemoteOptiGraph) means having to query the subgraph and get the number of nodes; probably not a big deal, but might require an extra fetch
    f = @spawnat rgraph.worker begin
        n = add_node(localpart(rgraph.graph)[1], label=sym)
        (n.idx, n.label)
    end
    node_tuple = fetch(f)
    return RemoteNodeRef(rgraph, node_tuple[1], node_tuple[2])
end

function node_to_remote_ref(rgraph::RemoteOptiGraph, node::OptiNode) #ISSUE: can go from node to graph, but graph to node is hard
    return RemoteNodeRef(rgraph, node.idx, node.label)
end

function var_to_remote_ref(rgraph::RemoteOptiGraph, var::NodeVariableRef)
    rnode = node_to_remote_ref(rgraph, var.node)
    local_node = var.node
    graph = local_node.source_graph.x
    name = Base.string(graph.backend.graph_to_element_map[var.index])
    return RemoteVarRef(rnode, var.index, Symbol(name))
    #TODO: decided if the name should be a string or a symbol; I think I am switching between these a lot
end

function get_node(rgraph::RemoteOptiGraph, node::RemoteNodeRef)
    lg = local_graph(rgraph)

    #TODO: Make this more efficient
    for n in all_nodes(lg)
        if n.idx == node.node_idx
            return n
        end
    end
    
    error("Node $node not detected in RemoteGraph $rgraph")
end

function add_variable(node::RemoteNodeRef, name::Symbol=Symbol(""))
    rgraph = node.remote_graph

    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        local_node = get_node(rgraph, node)
        new_var = @variable(local_node, base_name = String(name))
        new_var.index
    end

    moi_idx = fetch(f)
    return RemoteVarRef(node, moi_idx, name)
end

function node_to_remote_ref(rgraph::RemoteOptiGraph, node::OptiNode) #ISSUE: can go from node to graph, but graph to node is hard
    return RemoteNodeRef(rgraph, node.idx, node.label)
end

function get_node(graph::OptiGraph, sym::Symbol)
    for n in all_nodes(graph)
        if n.label.x == sym
            return n
        end 
    end
    error("Symbol $sym not saved on remotegraph")
end

function Base.getindex(rgraph::RemoteOptiGraph, sym::Symbol)
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        local_node = Plasmo.get_node(lg, sym)
        (local_node.idx, local_node.label)
    end
    node_tuple = fetch(f)

    return RemoteNodeRef(rgraph, node_tuple[1], node_tuple[2])
end
#TODO: Each call will create a new RemoteNodeRef; need to figure out how to not duplicate these; maybe we have a dictionary of node symbols to node refs in the RemoteOptiGraph? 
# Need to double check this. If I try to set two of the above functions equal to each other for different calls of the same node (even using ===), it says it is true; looking online,it looks like this might result in different allocations in memory but you cannot tell on the Julia language level

function Base.getindex(rnode::RemoteNodeRef, sym::Symbol)
    rgraph = rnode.remote_graph
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        local_node = Plasmo.get_node(lg, rnode)

        new_var.index # get this from the symbol

        (local_node.idx, local_node.label)
    end
    node_tuple = fetch(f)

    return RemoteNodeRef(rgraph, node_tuple[1], node_tuple[2])
end



# Need this to work for @variable macro; this currently does not work
function JuMP.add_variable(node::RemoteNodeRef, v::JuMP.AbstractVariable, name::String="")
    rgraph = node.remote_graph

    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        remote_node = get_node(rgraph, node)
        new_var = @variable(remote_node)
        new_var.index
    end
    moi_idx = fetch(f)
    println(moi_idx)
    return RemoteVarRef(node, moi_idx, Symbol(name))
    # find node on remote; 
    # send (fetch) name from local to remote
    # send (fetch) v from local to remote
    # do JuMP.add_variable with this to node
    # fetch MOI index for new var
    # return remote_var_ref
    #TODO: Make sure this works for vector of variables
end

# get_variable_from_remote - pass var_name to get remote_ref for linking constraints

function JuMP.all_variables(rgraph::RemoteOptiGraph)
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        all_vars = JuMP.all_variables(lg)
        [var_to_remote_ref(rgraph, var) for var in all_vars] #TODO: Move the var_to_remote_ref outside @spawnat
    end
    
    return fetch(f)
end



function Base.string(rnode::RemoteNodeRef)
    return String(rnode.node_label.x)
end
Base.print(io::IO, rnode::RemoteNodeRef) = Base.print(io, Base.string(rnode))
Base.show(io::IO, rnode::RemoteNodeRef) = Base.print(io, rnode)

function Base.string(rgraph::RemoteOptiGraph)
    return "RemoteOptiGraph"
end
Base.print(io::IO, graph::RemoteOptiGraph) = Base.print(io, Base.string(graph))
Base.show(io::IO, graph::RemoteOptiGraph) = Base.print(io, graph)

function Base.string(rvar::RemoteVarRef)
    return Base.string(rvar.node) * "[" * String(rvar.name) * "]"
end

Base.print(io::IO, rvar::RemoteVarRef) = Base.print(io, Base.string(rvar))
Base.show(io::IO, rvar::RemoteVarRef) = Base.print(io, rvar)

#TODO: Need to extend @optimize, value, etc.
#TODO: I am assuming gensym (for generating node or graph labels) will not necessarily guarantee differences across workers; not sure if this is an issue yet, but something to keep in mind


# function Base.setindex!(rnode::RemoteNodeRef, value::Any, name::Symbol)
#     rgraph = rnode.remote_graph
#     f = @spawnat rgraph.worker begin 
#         graph = local_graph(rgraph)
#         node = graph.optinode_map[rnode.node_index]
#         Base.setindex!(node, value, name)
#     end
#     return nothing
# end

# function Base.getindex(rnode::RemoteNodeRef, name::Symbol)
#     rgraph = rnode.remote_graph
#     f = @spawnat rgraph.worker begin 
#         graph = local_graph(rgraph)
#         node = graph.optinode_map[rnode.node_index]
#         Base.getindex(node, name)
#     end
#     return fetch(f)
# end

# # TODO: figure out how we build distributed models
# function JuMP.add_variable(rnode::RemoteNodeRef, v::JuMP.ScalarVariable, name::String="")
#     rgraph = rnode.remote_graph
#     f = @spawnat rgraph.worker begin 
#         graph = local_graph(rgraph)
#         node = graph.optinode_map[rnode.node_index]
#         JuMP.add_variable(node, v, name)
#     end
#     # need to return some kind of remote reference. this would fetch the whole graph.
#     # if we do this; then we have to support all kinds of operations on the remote variable reference
#     return fetch(f)
# end

# function JuMP.object_dictionary(rnode::RemoteNodeRef)
#     rgraph = rnode.remote_graph
#     f = @spawnat rgraph.worker begin
#         graph = localpart(rgraph.graph)[1]
#         node = graph.optinode_map[rnode.node_index]
#         obj_dict = JuMP.object_dictionary(node)
#     end 
#     return fetch(f)
# end
# A remote graph tracks its worker and a DistributedArray as a persistent reference to the graph on the worker
# The remote graph can also have a subset of other, nested remote graphs that are distributed on other workers

abstract type AbstractRemoteEdgeRef <: JuMP.AbstractModel end
abstract type AbstractRemoteNodeRef <: JuMP.AbstractModel end

const RemoteEdgeConstraintRef = JuMP.ConstraintRef{
    <:AbstractRemoteEdgeRef,MOI.ConstraintIndex{FT,ST},<:JuMP.AbstractShape
} where {FT<:MOI.AbstractFunction,ST<:MOI.AbstractSet}

# or should this be it's own mutable struct that is an abstractlinkconstraint

mutable struct EdgeData #TODO: merge the `constraints` attribute of the RemoteEdgeRef with this struct; I think the crefs should live on the graph, not on the edge structure
    optiedge_map::OrderedDict{Set{<:AbstractRemoteNodeRef}, AbstractRemoteEdgeRef}
    last_constraint_index::OrderedDict{AbstractRemoteEdgeRef, Int64}
end

mutable struct RemoteOptiGraph <: AbstractOptiGraph
    worker::Int
    graph::DArray{OptiGraph, 1, Vector{OptiGraph}} # I think this should only be allowed to be a length one vector. If it is anymore, than the user should just create a new RemoteOptiGraph object
    parent_graph::Union{Nothing, RemoteOptiGraph}
    subgraphs::Vector{RemoteOptiGraph} # These are nested remote optigraph objects; all remote optigraphs live on the main worker, but they contain a distributed optigraph that does not have to live on the main worker
    optiedges::Vector{<:AbstractRemoteEdgeRef}
    edge_data::EdgeData
    label::Symbol
end #TODO: Maybe add an obj_dict and node_obj_dict for saving and referencing remotenoderefs or RemoteVariableRefs

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
    constraint_refs::OrderedDict{MOI.ConstraintIndex, Plasmo.RemoteEdgeConstraintRef} #TODO: probably move this to the graph rather than being an attribute of the edge ref; see note on EdgeData struct
    constraints::OrderedDict{Plasmo.RemoteEdgeConstraintRef, JuMP.AbstractConstraint}
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
        Vector{Plasmo.RemoteEdgeRef}(), 
        EdgeData(),
        name #not sure yet whether the remote and local should have the same name, but doing that for now
    )
    return rgraph
end

function EdgeData()
    edge_data = EdgeData(
        OrderedDict{Set{RemoteNodeRef},RemoteEdgeRef}(), 
        OrderedDict{RemoteEdgeRef, Int64}(), 
    )
    return edge_data
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

function add_subgraph(rgraph::RemoteOptiGraph; worker::Int=1)
    new_rgraph = RemoteOptiGraph(worker=worker)
    push!(rgraph.subgraphs, new_rgraph)
    return new_rgraph
end

function add_subgraph(rgraph::RemoteOptiGraph, rsubgraph::RemoteOptiGraph)
    subgraphs = rgraph.subgraphs
    if rsubgraph in subgraphs
        println("$rsubgraph is already a subgraph of $rgraph")
    else
        push!(subgraphs, rsubgraph)
    end
    return nothing
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

function add_edge(
    rgraph::RemoteOptiGraph,
    rnodes::RemoteNodeRef...;
    label = Symbol(rgraph.label, Symbol(".e"), length(rgraph.optiedges)+1)
)
    if has_edge(rgraph, Set(rnodes))
        redge = get_edge(rgraph, Set(rnodes))
    else
        redge = RemoteEdgeRef(rgraph, OrderedSet(collect(rnodes)), OrderedDict{MOI.ConstraintIndex, Plasmo.RemoteEdgeConstraintRef}(), OrderedDict{Plasmo.RemoteEdgeConstraintRef, JuMP.AbstractConstraint}(), label)
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

function JuMP.add_constraint(
    rgraph::RemoteOptiGraph, con::JuMP.AbstractConstraint, name::String=""
)
    rnodes = collect_nodes(JuMP.jump_function(con))
    @assert length(rnodes) > 0
    length(rnodes) > 1 || error("Cannot create a linking constraint on a single node")
    redge = add_edge(rgraph, rnodes...)
    con = JuMP.model_convert(redge, con)
    cref = _build_constraint_ref(redge, con)
end

function _build_constraint_ref(redge::RemoteEdgeRef, con::JuMP.AbstractConstraint)
    # get moi function and set
    jump_func = JuMP.jump_function(con)
    moi_func = JuMP.moi_function(con)
    moi_set = JuMP.moi_set(con)

    # create constraint index and reference
    constraint_index = next_constraint_index(
        redge, typeof(moi_func), typeof(moi_set)
    )::MOI.ConstraintIndex{typeof(moi_func),typeof(moi_set)}
    cref = ConstraintRef(redge, constraint_index, JuMP.shape(con))

    redge.constraint_refs[constraint_index] = cref
    redge.constraints[cref] = con

    #TODO: define `containing_optigraphs` function like Plasmo does for OptiGraphs
    return cref
end

function JuMP.is_valid(edge::RemoteEdgeRef, cref::ConstraintRef)
    return edge === JuMP.owner_model(cref)# && MOI.is_valid(graph_backend(edge), cref)
end

function get_edge(cref::RemoteEdgeConstraintRef)
    return JuMP.owner_model(cref)
end

function JuMP.set_name(rnode::RemoteNodeRef, label::Symbol)
    rgraph = rnode.remote_graph

    f = @spawnat rgraph.worker begin
        lnode = get_node(rgraph, rnode)
        lnode.label.x = label
    end

    rnode.node_label.x = label
end



# Unclear if I need this function; it is defined in Plasmo, but it seems like the one for the remote graph should be sufficient? 
# function JuMP.add_constraint(
#     redge::RemoteEdgeRef, con::JuMP.AbstractConstraint, name::String=""
# )

# end

function next_constraint_index(
    redge::RemoteEdgeRef, ::Type{F}, ::Type{S}
)::MOI.ConstraintIndex{F,S} where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    source_data = source_graph(redge).edge_data
    if !haskey(source_data.last_constraint_index, redge)
        source_data.last_constraint_index[redge] = 0
    end
    source_data.last_constraint_index[redge] += 1
    return MOI.ConstraintIndex{F,S}(source_data.last_constraint_index[redge])
end


function node_to_remote_ref(rgraph::RemoteOptiGraph, node::OptiNode) #ISSUE: can go from node to graph, but graph to node is hard
    return RemoteNodeRef(rgraph, node.idx, node.label)
end

function var_to_remote_ref(rgraph::RemoteOptiGraph, var::NodeVariableRef)
    rnode = node_to_remote_ref(rgraph, var.node)
    local_node = var.node
    graph = local_node.source_graph.x
    return RemoteVariableRef(rnode, var.index, Symbol(name(var)))
    #TODO: decide if the name should be a string or a symbol; I think I am switching between these a lot
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

function JuMP.add_variable(rnode::RemoteNodeRef, v::JuMP.ScalarVariable, name::String="")
    rvref = _add_remote_node_variable(rnode, v, name)
    return rvref
end

function _add_remote_node_variable(rnode::RemoteNodeRef, v::JuMP.ScalarVariable, name::String="")
    rgraph = rnode.remote_graph
    sym = Symbol(name)

    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        lnode = get_node(rgraph, rnode)
        nvref = JuMP.add_variable(lnode, v, name)
        lg.element_data.node_obj_dict[(lnode, sym)] = nvref
        nvref.index
    end
    moi_idx = fetch(f)

    return RemoteVariableRef(rnode, moi_idx, sym)
end

function add_variable(node::RemoteNodeRef, name::Symbol=Symbol(""))
    rgraph = node.remote_graph

    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        local_node = get_node(rgraph, node)
        new_var = @variable(local_node, base_name = String(name))
        lg.element_data.node_obj_dict[(local_node, name)] = new_var
        new_var.index
    end

    moi_idx = fetch(f)
    return RemoteVariableRef(node, moi_idx, name)
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
        local_node = Plasmo.get_node(rgraph, rnode)
        var = local_node[sym]
        var.index # get this from the symbol
    end
    moi_idx = fetch(f)

    return RemoteVariableRef(rnode, moi_idx, sym)
end

# # Need this to work for @variable macro; this currently does not work
# function JuMP.add_variable(node::RemoteNodeRef, v::JuMP.AbstractVariable, name::String="")
#     rgraph = node.remote_graph

#     f = @spawnat rgraph.worker begin
#         lg = local_graph(rgraph)
#         remote_node = get_node(rgraph, node)
#         new_var = @variable(remote_node)
#         new_var.index
#     end
#     moi_idx = fetch(f)
#     return RemoteVariableRef(node, moi_idx, Symbol(name))
#     # find node on remote; 
#     # send (fetch) name from local to remote
#     # send (fetch) v from local to remote
#     # do JuMP.add_variable with this to node
#     # fetch MOI index for new var
#     # return remote_var_ref
#     #TODO: Make sure this works for vector of variables
# end

function JuMP.all_variables(rgraph::RemoteOptiGraph)
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        all_vars = JuMP.all_variables(lg)
        [var_to_remote_ref(rgraph, var) for var in all_vars] #TODO: Move the var_to_remote_ref outside @spawnat? Not sure if this is being called in the right place. May need to rethink this
    end
    
    return fetch(f)
end

function JuMP.optimize!(rgraph::RemoteOptiGraph)#TODO: Figure out how to support kwargs for this
    f = @spawnat rgraph.worker begin
        lg = local_graph(rgraph)
        JuMP.optimize!(lg)
    end
    return fetch(f)
end

function JuMP.set_optimizer(rgraph::RemoteOptiGraph, optimizer)
    remotecall_wait(rgraph.worker) do
        lg = local_graph(rgraph)    
        JuMP.set_optimizer(lg, optimizer)
    end
    return nothing
end

function JuMP.set_optimizer_attribute(rgraph::RemoteOptiGraph, pairs::Pair...)
    remotecall_wait(rgraph.worker) do
        lg = local_graph(rgraph)
        JuMP.set_optimizer_attribute(lg, pairs...)
    end
    return nothing
end #TODO: go through and decide if all my functions should be using `remotecall_wait` or `@spawnat`

# function for getting remote refs for a given variable? 

function add_link_constraint(rgraph::RemoteOptiGraph, expr::RemoteAffExpr, f::Function, rhs::T) where {T <: Real}

end

function Base.string(rnode::RemoteNodeRef)
    return String(rnode.node_label.x)
end
Base.print(io::IO, rnode::RemoteNodeRef) = Base.print(io, Base.string(rnode))
Base.show(io::IO, rnode::RemoteNodeRef) = Base.print(io, rnode)

function Base.string(redge::RemoteEdgeRef)
    return String(redge.label)
end
Base.print(io::IO, redge::RemoteEdgeRef) = Base.print(io, Base.string(redge))
Base.show(io::IO, redge::RemoteEdgeRef) = Base.print(io, redge)

function Base.string(rgraph::RemoteOptiGraph)
    return "RemoteOptiGraph"
end
Base.print(io::IO, graph::RemoteOptiGraph) = Base.print(io, Base.string(graph))
Base.show(io::IO, graph::RemoteOptiGraph) = Base.print(io, graph)

function Base.string(rvar::RemoteVariableRef)
    return Base.string(rvar.node) * "[" * String(rvar.name) * "]"
end

Base.print(io::IO, rvar::RemoteVariableRef) = Base.print(io, Base.string(rvar))
Base.show(io::IO, rvar::RemoteVariableRef) = Base.print(io, rvar)

function JuMP.index(rvar::RemoteVariableRef) return rvar.index end

function JuMP.owner_model(rvar::RemoteVariableRef) return rvar.node end

function JuMP.name(rvar::RemoteVariableRef) return Base.string(rvar) end

function source_graph(redge::RemoteEdgeRef) return redge.remote_graph end

function JuMP.is_valid(rnode::RemoteNodeRef, rvar::RemoteVariableRef)
    if rvar.node == rnode
        return true
    else
        return false
    end
end

function Base.setindex!(rnode::RemoteNodeRef, value, name::Symbol) #TODO: Consider whether we should do this differently without an object dictionary
    return nothing
end

#= #TODO: Figure out displaying constraints
function name(
    con_ref::ConstraintRef{RemoteEdgeRef,C},
) where {C<:MOI.ConstraintIndex}
    model = owner_model(con_ref)
    if !MOI.supports(backend(model), MOI.ConstraintName(), C)
        return ""
    end
    return MOI.get(model, MOI.ConstraintName(), con_ref)::String
end
=#

#TODO: I think perhaps we could make an abstractnodevariableref type which NodeVariableRef and RemoteVariableRef are subtypes of so that we can just have one set of MOI functions we are extending instead of two
JuMP.variable_ref_type(::Type{T} where {T<:RemoteOptiObject}) = RemoteVariableRef
JuMP.jump_function(::RemoteOptiObject, x::Number) = convert(Float64, x)

function JuMP.jump_function_type(::RemoteOptiObject, ::Type{MOI.VariableIndex})
    return RemoteVariableRef
end

# function JuMP.jump_function(obj::OptiObject, vidx::MOI.VariableIndex)
    # backend = graph_backend(obj)
    # node_var = JuMP.constraint_ref_with_index(backend, vidx)
    # node = node_var.node
    # return NodeVariableRef(node, node_var.index)
# end #TODO: Need to extend graph_backend for this

function MOI.ScalarAffineFunction(a::GenericAffExpr{C,<:RemoteVariableRef}) where {C}
    _assert_isfinite(a)
    terms = MOI.ScalarAffineTerm{C}[
        MOI.ScalarAffineTerm(t[1], index(t[2])) for t in linear_terms(a)
    ]
    return MOI.ScalarAffineFunction(terms, a.constant)
end

function JuMP.jump_function_type(
    obj::RemoteOptiObject, ::Type{MOI.ScalarAffineFunction{C}}
) where {C}
    return JuMP.GenericAffExpr{C,RemoteVariableRef}
end

function JuMP.jump_function(obj::RemoteOptiObject, f::MOI.ScalarAffineFunction{C}) where {C}
    return JuMP.GenericAffExpr{C,RemoteVariableRef}(obj, f)
end

function MOI.ScalarQuadraticFunction(q::GenericQuadExpr{C,RemoteVariableRef}) where {C}
    _assert_isfinite(q)
    qterms = MOI.ScalarQuadraticTerm{C}[_moi_quadratic_term(t) for t in quad_terms(q)]
    moi_aff = MOI.ScalarAffineFunction(q.aff)
    return MOI.ScalarQuadraticFunction(qterms, moi_aff.terms, moi_aff.constant)
end

function JuMP.jump_function_type(
    obj::RemoteOptiObject, ::Type{MOI.ScalarQuadraticFunction{C}}
) where {C}
    return JuMP.GenericQuadExpr{C,RemoteVariableRef}
end

function JuMP.jump_function(obj::RemoteOptiObject, f::MOI.ScalarQuadraticFunction{C}) where {C}
    return JuMP.GenericQuadExpr{C,RemoteVariableRef}(obj, f)
end

function JuMP.jump_function_type(obj::RemoteOptiObject, ::Type{MOI.ScalarNonlinearFunction})
    V = JuMP.variable_ref_type(typeof(obj))
    return JuMP.GenericNonlinearExpr{V}
end

function JuMP.jump_function(node::RemoteNodeRef, f::MOI.ScalarNonlinearFunction)
    V = JuMP.variable_ref_type(typeof(node))
    ret = JuMP.GenericNonlinearExpr{V}(f.head, Any[])
    stack = Tuple{JuMP.GenericNonlinearExpr,Any}[]
    for arg in reverse(f.args)
        push!(stack, (ret, arg))
    end
    while !isempty(stack)
        parent, arg = pop!(stack)
        if arg isa MOI.ScalarNonlinearFunction
            new_ret = JuMP.GenericNonlinearExpr{V}(arg.head, Any[])
            push!(parent.args, new_ret)
            for child in reverse(arg.args)
                push!(stack, (new_ret, child))
            end
        else
            push!(parent.args, JuMP.jump_function(node, arg))
        end
    end
    return ret
end

function JuMP.jump_function(edge::RemoteEdgeRef, f::MOI.ScalarNonlinearFunction)
    V = JuMP.variable_ref_type(typeof(edge))
    ret = JuMP.GenericNonlinearExpr{V}(f.head, Any[])
    stack = Tuple{JuMP.GenericNonlinearExpr,Any}[]
    for arg in reverse(f.args)
        push!(stack, (ret, arg))
    end
    while !isempty(stack)
        parent, arg = pop!(stack)
        if arg isa MOI.ScalarNonlinearFunction
            new_ret = JuMP.GenericNonlinearExpr{V}(arg.head, Any[])
            push!(parent.args, new_ret)
            for child in reverse(arg.args)
                push!(stack, (new_ret, child))
            end
        else
            push!(parent.args, JuMP.jump_function(edge, arg))
        end
    end
    return ret
end

function JuMP.jump_function(graph::RemoteOptiGraph, f::MOI.ScalarNonlinearFunction)
    V = JuMP.variable_ref_type(typeof(graph))
    ret = JuMP.GenericNonlinearExpr{V}(f.head, Any[])
    stack = Tuple{JuMP.GenericNonlinearExpr,Any}[]
    for arg in reverse(f.args)
        push!(stack, (ret, arg))
    end
    while !isempty(stack)
        parent, arg = pop!(stack)
        if arg isa MOI.ScalarNonlinearFunction
            new_ret = JuMP.GenericNonlinearExpr{V}(arg.head, Any[])
            push!(parent.args, new_ret)
            for child in reverse(arg.args)
                push!(stack, (new_ret, child))
            end
        else
            push!(parent.args, JuMP.jump_function(graph, arg))
        end
    end
    return ret
end

function JuMP._error_if_cannot_register(rnode::RemoteNodeRef, name::Symbol)
    return nothing
end


# function JuMP.GenericAffExpr{C,RemoteVariableRef}(
#     node::RemoteNodeRef, f::MOI.ScalarAffineFunction
# ) where {C}
#     aff = GenericAffExpr{C,RemoteVariableRef}(f.constant)
#     backend = graph_backend(node)
#     for t in f.terms
#         node_var_index = JuMP.constraint_ref_with_index(backend, t.variable).index
#         JuMP.add_to_expression!(aff, t.coefficient, NodeVariableRef(node, node_var_index))
#     end
#     return aff
# end

# function JuMP.GenericAffExpr{C,NodeVariableRef}(
#     edge::OptiEdge, f::MOI.ScalarAffineFunction
# ) where {C}
#     aff = GenericAffExpr{C,NodeVariableRef}(f.constant)
#     backend = graph_backend(edge)
#     # build JuMP Affine Expression over edge variables
#     for t in f.terms
#         node_var = JuMP.constraint_ref_with_index(backend, t.variable)
#         node = node_var.node
#         node_var_index = node_var.index
#         JuMP.add_to_expression!(aff, t.coefficient, NodeVariableRef(node, node_var_index))
#     end
#     return aff
# end


# function JuMP.GenericAffExpr{C,NodeVariableRef}(
#     graph::OptiGraph, f::MOI.ScalarAffineFunction
# ) where {C}
#     aff = GenericAffExpr{C,NodeVariableRef}(f.constant)
#     # build JuMP Affine Expression over func variables
#     backend = graph_backend(graph)
#     for t in f.terms
#         node_var = JuMP.constraint_ref_with_index(backend, t.variable)
#         node = node_var.node
#         node_var_index = node_var.index
#         JuMP.add_to_expression!(aff, t.coefficient, NodeVariableRef(node, node_var_index))
#     end
#     return aff
# end





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
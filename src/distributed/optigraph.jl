# Enable printing the graph
function Base.string(rgraph::RemoteOptiGraph)
    return "RemoteOptiGraph"
end
Base.print(io::IO, graph::RemoteOptiGraph) = Base.print(io, Base.string(graph))
Base.show(io::IO, graph::RemoteOptiGraph) = Base.print(io, graph)

function source_graph(rgraph::RemoteOptiGraph) return rgraph.parent_graph end

function Base.getindex(rgraph::RemoteOptiGraph, sym::Symbol)
    if haskey(rgraph.obj_dict, sym)
        return rgraph.obj_dict[sym]
    else
        darray = rgraph.graph

        f = @spawnat rgraph.worker begin
            lgraph = localpart(darray)[1]
            if haskey(lgraph.obj_dict, sym)
                obj = lgraph.obj_dict[sym]
            else
                error("No object with name $sym is registered on given OptiGraph")
            end
            _convert_local_to_proxy(lgraph, obj)
        end
        pobj = fetch(f)
        return _convert_proxy_to_remote(rgraph, pobj)
    end
end

JuMP.value_type(::Type{RemoteOptiGraph}) = Float64

function JuMP.object_dictionary(rgraph::RemoteOptiGraph)
    return rgraph.obj_dict
end

#TODO: print OptiGraph nicer
#TODO: implement summary option that will fetch data

###### Functions for getting the remote data from a RemoteOptiGraph ######
function local_graph(rgraph::RemoteOptiGraph)
    return localpart(rgraph.graph)[1]
end

function local_graph(darray::DistributedArrays.DArray)
    return localpart(darray)[1]
end

function print_local_graph(rgraph::RemoteOptiGraph)
    @spawnat rgraph.worker println(localpart(rgraph.graph)[1])
    return nothing
end

function get_local_graph(rgraph::RemoteOptiGraph)
    f = @spawnat rgraph.worker localpart(rgraph.graph)[1]
    return fetch(f)
end

"""
    Plasmo.add_subgraph(rgraph::RemoteOptigraph; worker::Int=1)

Add a RemoteOptiGraph as a subgraph to `rgraph`. This instantiates a new RemoteOptiGraph
that contains a remote graph on worker `worker`
"""
function add_subgraph(rgraph::RemoteOptiGraph; worker::Int=1)
    new_rgraph = RemoteOptiGraph(worker=worker)
    push!(rgraph.subgraphs, new_rgraph)
    new_rgraph.parent_graph = rgraph
    return new_rgraph
end

"""
    add_subgraph(rgraph::RemoteOptiGraph, rsubgraph::RemoteOptiGraph)

Add `rsubgraph` as a subgraph to `rgraph`
"""
function add_subgraph(rgraph::RemoteOptiGraph, rsubgraph::RemoteOptiGraph)
    subgraphs = rgraph.subgraphs
    if rsubgraph in subgraphs
        println("$rsubgraph is already a subgraph of $rgraph")
    else
        push!(subgraphs, rsubgraph)
        rsubgraph.parent_graph = rgraph
    end
    return nothing
end 

"""
    Plasmo.all_nodes(rgraph::RemoteOptiGraph)

Returns a vector of RemoteNodeRefs for all nodes stored on remote OptiGraphs on 
`rgraph` and all of its subgraphs
"""
function all_nodes(rgraph::RemoteOptiGraph)
    darray = rgraph.graph

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        nodes = Plasmo.all_nodes(lgraph)
        [_convert_local_to_proxy(lgraph, node) for node in nodes]
    end
    pnodes = fetch(f)
    nodes = [_convert_proxy_to_remote(rgraph, node) for node in pnodes]
    for g in rgraph.subgraphs
        append!(nodes, all_nodes(g))
    end
    return nodes
end

"""
    Plasmo.local_nodes(rgraph::RemoteOptiGraph)

Returns a vector of RemoteNodeRefs for all nodes stored on `rgraph`'s remote OptiGraph. 
This returns all nodes on remote OptiGraph, but none of the nodes on the sub-RemoteOptiGraphs. 

NOTE: the remote OptiGraph stored on `rgraph` may contain multiple sub-opitgraphs, and this 
function still returns all nodes contained on these "local" subgraphs.
"""
function local_nodes(rgraph::RemoteOptiGraph)
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        nodes = Plasmo.all_nodes(lgraph)
        [_convert_local_to_proxy(lgraph, node) for node in nodes]
    end
    pnodes = fetch(f)
    nodes = [_convert_proxy_to_remote(rgraph, node) for node in pnodes]
    return nodes
end

function get_node(rgraph::RemoteOptiGraph, idx::Int)
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lnode = get_node(lgraph, idx)
        _convert_local_to_proxy(lgraph, lnode)
    end
    pnode = fetch(f)
    return _convert_proxy_to_remote(rgraph, pnode)
end

function num_local_nodes(rgraph::RemoteOptiGraph)
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        num_local_nodes(lgraph)
    end
    return fetch(f)
end

"""
    Plasmo.all_subgraphs(rgraph::RemoteOptiGraph)

Returns a vector of all sub-RemoteOptiGraphs contained in `rgraph` and all 
sub-RemoteOptiGraphs nested within any of these sub-RemoteOptiGraphs.
"""
function all_subgraphs(rgraph::RemoteOptiGraph)
    subs = collect(rgraph.subgraphs)
    for subgraph in rgraph.subgraphs
        subs = [subs; all_subgraphs(subgraph)]
    end
    return subs
end

"""
    Plasmo.local_subgraphs(rgraph::RemoteOptiGraph)

Returns the vector of sub-RemoteOptiGraphs stored directly on `rgraph`
Does not include subgraphs nested in subgraphs
"""
function local_subgraphs(rgraph::RemoteOptiGraph)
    return rgraph.subgraphs
end

"""
    Plasmo.num_local_subgraphs(rgraph::RemoteOptiGraph)

Returns the number of sub-RemoteOptiGraphs stored directly on `rgraph`
Does not include subgraphs nested in subgraphs
"""
function num_local_subgraphs(rgraph::RemoteOptiGraph)
    return length(rgraph.subgraphs) 
end

"""
    Plasmo.num_subgraphs(rgraph)

Returns the number of all sub-RemoteOptiGraphs contained in `rgraph`, including
subgraphs of subgraphs
"""
function num_subgraphs(rgraph::RemoteOptiGraph)
    n_subs = num_local_subgraphs(rgraph)
    for subgraph in rgraph.subgraphs
        n_subs += num_subgraphs(subgraph)
    end
end

function num_local_elements(rgraph::RemoteOptiGraph)
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        Plasmo.num_elements(lgraph)
    end
    return fetch(f)
end

function num_elements(rgraph::RemoteOptiGraph)
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        Plasmo.num_local_elements(lgraph)
    end
    pelements = fetch(f)
    relements = _convert_proxy_to_remote(rgraph, pelements)
    for subgraph in rgraph.subgraphs
        relements = [relements; num_elements(subgraph)]
    end
    return relements
end

function local_elements(rgraph::RemoteOptiGraph)
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        elements = Plasmo.all_elements(lgraph)
        pelements = _convert_local_to_proxy(lgraph, elements)
    end
    pelements = fetch(f)
    return _convert_proxy_to_local(rgraph, pelements)
end

function all_elements(rgraph::RemoteOptiGraph)
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        elements = Plasmo.all_elements(lgraph)
        pelements = _convert_local_to_proxy(lgraph, elements)
    end
    pelements = fetch(f)
    relements = _convert_proxy_to_local(rgraph, pelements)
    for subgraph in rgraph.subgraphs
        relements = [relements; all_elements(subgraph)]
    end
    return relements
end

# These are a little confusing in that these are counting the link constraints
# on the graph stored on the remote. It is NOT counting the link constraints on 
# the RemoteOptiEdge, but rather the number of link constraints that exist on 
# the RemoteEdgeRef objects. The `num_remote_link_constraints` returns the 
# number of constraints on rgraph's edges
function num_local_link_constraints(
    rgraph::RemoteOptiGraph,
    func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
    set_type::Type{<:MOI.AbstractSet},
)
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        sum(JuMP.num_constraints.(all_edges(lgraph), Ref(func_type), Ref(set_type)))
    end
    return fetch(f)
end

function num_local_link_constraints(rgraph::RemoteOptiGraph)
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        num_link_constraints(lgraph)
    end
    return fetch(f)
end

function num_link_constraints(
    rgraph::RemoteOptiGraph,
    func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
    set_type::Type{<:MOI.AbstractSet},
)
    nconstraints = num_local_link_constraints(rgraph, func_type, set_type)
    for subgraph in rgraph.subgraphs
        nconstraints += num_link_constraints(subgraph, func_type, set_type)
    end
    return nconstraints
end

function num_link_constraints(rgraph::RemoteOptiGraph)
    nconstraints = num_local_link_constraints(rgraph)
    for subgraph in rgraph.subgraphs
        nconstraints += num_link_constraints(subgraph)
    end
    return nconstraints
end

function num_local_remote_link_constraints(rgraph::RemoteOptiGraph)
    n_remote_constraints = 0
    for edge in rgraph.optiedges
        n_remote_constraints += length(edge.constraints)
    end
    return n_remote_constraints
end

function num_remote_link_constraints(rgraph::RemoteOptiGraph)
    n_remote_constraints = num_local_remote_link_constraints(rgraph)
    for subgraph in rgraph.subgraphs
        n_remote_constraints += num_remote_link_constraints(rgraph)
    end
    return n_remote_constraints
end

function local_link_constraints(
    rgraph::RemoteOptiGraph,
    func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
    set_type::Type{<:MOI.AbstractSet},
)
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        cons = vcat(all_constraints.(local_edges(lgraph), Ref(func_type), Ref(set_type))...)
        _convert_local_to_proxy(lgraph, cons)
    end
    pcons = fetch(f)
    return _convert_proxy_to_remote(rgraph, pcons)
end

function local_link_constraints(rgraph::RemoteOptiGraph)
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        cons = local_link_constraints(lgraph)
        _convert_local_to_proxy(lgraph, cons)
    end
    pcons = fetch(f)
    return _convert_proxy_to_remote(rgraph, pcons)
end

function all_link_constraints(
    rgraph::RemoteOptiGraph,
    func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
    set_type::Type{<:MOI.AbstractSet},
)
    remote_constraints = local_link_constraints(rgraph, func_type, set_type)
    for subgraph in rgraph.subgraphs
        remote_constraints = [remote_constraints; all_link_constraints(rgraph, func_type, set_type)]
    end
    return remote_constraints
end

function all_link_constraints(rgraph::RemoteOptiGraph)
    remote_constraints = local_link_constraints(rgraph)
    for subgraph in rgraph.subgraphs
        remote_constraints = [remote_constraints; all_link_constraints(rgraph)]
    end
    return remote_constraints
end

function num_local_constraints(
    rgraph::RemoteOptiGraph,
    func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
    set_type::Type{<:MOI.AbstractSet},
)
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        JuMP.num_constraints(lgraph, func_type, set_type)
    end
    return fetch(f)
end

function num_local_constraints(rgraph::RemoteOptiGraph; count_variable_in_set_constraints=false)
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        JuMP.num_constraints(lgraph, count_variable_in_set_constraints = count_variable_in_set_constraints)
    end
    return fetch(f)
end

function JuMP.num_constraints(
    rgraph::RemoteOptiGraph,
    func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
    set_type::Type{<:MOI.AbstractSet},
)
    nconstraints = num_local_constraints(rgraph, func_type, set_type)
    for subgraph in rgraph.subgraphs
        nconstraints += JuMP.num_constraints(subgraph, func_type, set_type)
    end
    return nconstraints
end

function JuMP.num_constraints(rgraph::RemoteOptiGraph; count_variable_in_set_constraints = false)
    nconstraints = num_local_constraints(rgraph; count_variable_in_set_constraints=count_variable_in_set_constraints)
    for subgraph in rgraph.subgraphs
        nconstraints += JuMP.num_constraints(subgraph;count_variable_in_set_constraints=count_variable_in_set_constraints)
    end
    return nconstraints
end
#TODO: local_constraints
#TODO: remote constraints num and retrieve for 


function JuMP.index(rgraph::RemoteOptiGraph, nvref::RemoteVariableRef)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, nvref)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _convert_proxy_to_local(lgraph, pvar)
        JuMP.index(lgraph, lvar)
    end
    return fetch(f)
end

"""
    Plasmo.containing_optigraphs(robj::RemoteOptiObject)

returns all the RemoteOptiGraphs that contain the RemoteOptiObject
"""
function containing_optigraphs(robj::RemoteOptiObject)
    sg = source_graph(robj)
    if isnothing(sg.parent_graph)
        return [sg]
    else
        return [sg; containing_optigraphs(sg)]
    end    
end

"""
    JuMP.add_constraint(rgraph::RemoteOptiGraph, con::JuMP.AbstractConstraint, name::String="")

Add a new constraint to `rgraph` (which will be placed on `rgraph`'s remote OptiGraph if 
applicable). This method is called internally when a user uses the JuMP.@constraint macro.
"""
function JuMP.add_constraint(
    rgraph::RemoteOptiGraph, con::JuMP.AbstractConstraint, name::String=""
)
    rnodes = collect_nodes(JuMP.jump_function(con))
    @assert length(rnodes) > 0
    length(rnodes) > 1 || error("Cannot create a linking constraint on a single node")

    if all(n -> n.remote_graph == rgraph, rnodes)
        rcref = _build_constraint_ref(rgraph, con, name=name)
    else
        redge = add_edge(rgraph, rnodes...)
        con = JuMP.model_convert(redge, con)
        rcref = _build_constraint_ref(redge, con)
    end
    return rcref
end 

# build the constraint reference
function _build_constraint_ref(rgraph::RemoteOptiGraph, con::JuMP.AbstractConstraint; name::String="")
    darray = rgraph.graph
    pexpr = _convert_remote_to_proxy(rgraph, con.func)
    con_set = con.set

    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        new_expr = _convert_proxy_to_local(lgraph, pexpr)
        lcon = JuMP.ScalarConstraint(new_expr, con_set)
        cref = JuMP.add_constraint(lgraph, lcon, name)
        pcref = _convert_local_to_proxy(lgraph, cref)
        pcref
    end
    pcref = fetch(f)
    return _convert_proxy_to_remote(rgraph, pcref)
end

###### Support optimization interface for graphs ######

function JuMP.optimize!(rgraph::RemoteOptiGraph)#TODO: Figure out how to support kwargs for this
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        JuMP.optimize!(lgraph)
    end
    return nothing
end

function JuMP.set_optimizer(rgraph::RemoteOptiGraph, optimizer)
    darray = rgraph.graph
    remotecall_wait(rgraph.worker) do
        lgraph = localpart(darray)[1]
        JuMP.set_optimizer(lgraph, optimizer)
    end
    return nothing
end

function JuMP.set_optimizer_attribute(rgraph::RemoteOptiGraph, pairs::Pair...)
    darray = rgraph.graph
    remotecall_wait(rgraph.worker) do
        lgraph = localpart(darray)[1]
        JuMP.set_optimizer_attribute(lgraph, pairs...)
    end
    return nothing
end #TODO: go through and decide if all my functions should be using `remotecall_wait` or `@spawnat`

function JuMP.set_objective(
    rgraph::RemoteOptiGraph, sense::MOI.OptimizationSense, func::JuMP.AbstractJuMPScalar
)
    darray = rgraph.graph
    pfunc = _convert_remote_to_proxy(rgraph, func)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        new_func = _convert_proxy_to_local(lgraph, pfunc)
        JuMP.set_objective(lgraph, sense, new_func)
    end
    return func
end

function JuMP.set_objective_function(
    rgraph::RemoteOptiGraph, func::JuMP.AbstractJuMPScalar
)
    darray = rgraph.graph
    pfunc = _convert_remote_to_proxy(rgraph, func)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        new_func = _convert_proxy_to_local(lgraph, pfunc)
        JuMP.set_objective_function(lgraph, new_func)
    end
    return func
end

function JuMP.set_objective_sense(
    rgraph::RemoteOptiGraph, sense::MOI.OptimizationSense
)
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        JuMP.set_objective_sense(lgraph, sense)
    end
    return nothing
end

function set_to_node_objectives(rgraph::RemoteOptiGraph)
    darray = rgraph.graph
    @spawnat rgraph.worker set_to_node_objectives(localpart(darray)[1])
    return nothing
end

function JuMP.objective_value(rgraph::RemoteOptiGraph)
    darray = rgraph.graph
    f = @spawnat rgraph.worker JuMP.objective_value(localpart(darray)[1])
    return fetch(f)
end

function JuMP.dual_objective_value(rgraph::RemoteOptiGraph)
    darray = rgraph.graph
    f = @spawnat rgraph.worker JuMP.dual_objective_value(localpart(darray)[1])
    return fetch(f)
end

function JuMP.objective_function(rgraph::RemoteOptiGraph)
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lobj_func = JuMP.objective_function(lgraph)
        robj_func = _convert_local_to_proxy(lgraph, lobj_func)
        robj_func
    end 
    pobj_func = fetch(f)
    return _convert_proxy_to_remote(rgraph, pobj_func)
end

function JuMP.set_objective_coefficient(
    rgraph::RemoteOptiGraph, variable::RemoteVariableRef, coeff::Real
)
    darray = rgraph.graph
    pvar = _convert_remote_to_proxy(rgraph, variable)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _convert_proxy_to_local(lgraph, pvar)
        JuMP.set_objective_coefficient(lgraph, lvar, coeff)
    end
    return nothing
end

function JuMP.set_objective_coefficient(
    rgraph::RemoteOptiGraph,
    variables::AbstractVector{<:RemoteVariableRef},
    coeffs::AbstractVector{<:Real},
)
    darray = rgraph.graph
    pvars = _convert_remote_to_proxy(rgraph, variables)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar = _convert_proxy_to_local(lgraph, pvars)
        JuMP.set_objective_coefficient(lgraph, lvar, coeffs)
    end
    return nothing
end

function JuMP.set_objective_coefficient(
    rgraph::RemoteOptiGraph, variable_1::RemoteVariableRef, variable_2::RemoteVariableRef, coeff::Real
)
    darray = rgraph.graph
    pvar1 = _convert_remote_to_proxy(rgraph, variable_1)
    pvar2 = _convert_remote_to_proxy(rgraph, variable_2)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar1 = _convert_proxy_to_local(lgraph, pvar1)
        lvar2 = _convert_proxy_to_local(lgraph, pvar2)
        JuMP.set_objective_coefficient(lgraph, lvar1, lvar2, coeff)
    end
    return nothing
end

function JuMP.set_objective_coefficient(
    rgraph::RemoteOptiGraph,
    variables_1::AbstractVector{<:RemoteVariableRef},
    variables_2::AbstractVector{<:RemoteVariableRef},
    coeffs::AbstractVector{<:Real},
)
    darray = rgraph.graph
    pvar1 = _convert_remote_to_proxy(rgraph, variables_1)
    pvar2 = _convert_remote_to_proxy(rgraph, variables_2)
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        lvar1 = _convert_proxy_to_local(lgraph, pvar1)
        lvar2 = _convert_proxy_to_local(lgraph, pvar2)
        JuMP.set_objective_coefficient(lgraph, lvar1, lvar2, coeffs)
    end
    return nothing
end

function has_node_objective(rgraph::RemoteOptiGraph)
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        has_node_objective(lgraph)
    end
    return fetch(f)
end

function node_objective_type(rgraph::RemoteOptiGraph)
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        node_objective_type(lgraph)
    end
    return fetch(f)
end

function JuMP.termination_status(rgraph::RemoteOptiGraph)
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        JuMP.termination_status(lgraph)
    end
    return fetch(f)
end

function JuMP.relative_gap(rgraph::RemoteOptiGraph)
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        JuMP.relative_gap(lgraph)
    end
    return fetch(f)
end

function JuMP.objective_bound(rgraph::RemoteOptiGraph)
    darray = rgraph.graph
    f = @spawnat rgraph.worker begin
        lgraph = localpart(darray)[1]
        JuMP.objective_bound(lgraph)
    end
    return fetch(f)
end

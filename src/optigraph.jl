"""
    HyperGraphBackend

Graph backend corresponding to a Plasmo.jl `HyperGraph` object.  A `HyperGraphBackend` is used to do graph analysis on an optigraph
by mapping optigraph elements to hypergraph elements.
"""
mutable struct HyperGraphBackend
    hypergraph::HyperGraph
    hyper_map#::ProjectionMap
    update_backend::Bool  #flag that graph backend needs to be re-created when querying graph attributes
end
##############################################################################
# OptiGraph
##############################################################################
"""
    OptiGraph()

Create an empty OptiGraph. An OptiGraph extends a JuMP.AbstractModel and supports most JuMP.Model functions.
"""
mutable struct OptiGraph <: AbstractOptiGraph #<: JuMP.AbstractModel
    #Topology
    optinodes::Vector{OptiNode}                  #Local optinodes
    optiedges::Vector{OptiEdge}                  #Local optiedges
    node_idx_map::Dict{OptiNode,Int64}           #Local map of optinodes to indices
    edge_idx_map::Dict{OptiEdge,Int64}           #Local map of optiedges indices
    subgraphs::Vector{AbstractOptiGraph}         #Subgraphs contained in the optigraph
    optiedge_map::OrderedDict{Set,OptiEdge}      #Sets of optinodes that map to an optiedge

    #Objective
    objective_sense::MOI.OptimizationSense
    objective_function::JuMP.AbstractJuMPScalar

    #IDEA: An optigraph optimizer can be a MOI model.  For standard optimization solvers, we can either 1) aggregate a MOI backend on the fly using optinodes or 2) build up the MOI backend with nodes simultaneously
    moi_backend::Union{Nothing,MOI.ModelLike}

    #IDEA: graph_backend is used for hypergraph topology functions (e.g. neighbors,expand,etc...)
    graph_backend::Union{Nothing,HyperGraphBackend}

    bridge_types::Set{Any}

    obj_dict::Dict{Symbol,Any}

    ext::Dict{Symbol,Any} #Extension Information

    id::Symbol

    is_dirty::Bool

    #Constructor
    function OptiGraph()
        optigraph = new(
            Vector{OptiNode}(),
            Vector{OptiEdge}(),
            Dict{OptiNode,Int64}(),
            Dict{OptiEdge,Int64}(),
            Vector{OptiGraph}(),
            OrderedDict{OrderedSet,OptiEdge}(),
            MOI.FEASIBILITY_SENSE,
            zero(JuMP.GenericAffExpr{Float64,JuMP.AbstractVariableRef}),
            nothing,
            nothing,
            Set{Any}(),
            Dict{Symbol,Any}(),
            Dict{Symbol,Any}(),
            gensym(),
            true,
        )
        graph_backend = GraphBackend(optigraph)
        optigraph.moi_backend = graph_backend
        return optigraph
    end
end

#Create an OptiGraph given a set of optinodes and optiedges
function OptiGraph(nodes::Vector{OptiNode}, edges::Vector{OptiEdge})
    #TODO
    #is_valid_optigraph(nodes,edges) || error("Cannot create optigraph from given nodes and edges.  At least one edge node is not in the provided vector of optinodes.")
    graph = OptiGraph()
    for node in nodes
        add_node!(graph, node)
    end
    for edge in edges
        push!(graph.optiedges, edge)
    end
    graph.node_idx_map = Dict([(node, i) for (i, node) in enumerate(nodes)])
    graph.edge_idx_map = Dict([(edge, i) for (i, edge) in enumerate(edges)])
    return graph
end

#Broadcast over graph without using `Ref`
Base.broadcastable(graph::OptiGraph) = Ref(graph)

function _is_valid_optigraph(nodes::Vector{OptiNode}, edges::Vector{OptiEdge})
    edge_nodes = union(optinodes.(edges)...)
    return issubset(edge_nodes, nodes)
end

"""
    optigraph_reference(graph::OptiGraph)::OptiGraph

Create a new optigraph with the same optinodes and optiedges as `graph`. Useful for defining an optigraph over
existing nodes and edges without recreating them. Note that any changes to the optinodes and optiedges
in the returned optigraph will take place in the original `graph`.
"""
optigraph_reference(graph::OptiGraph) = OptiGraph(all_nodes(graph), all_edges(graph))
@deprecate ModelGraph OptiGraph
########################################################
# OptiGraph Interface
########################################################
#Backend Check
function _flag_graph_backend!(graph::OptiGraph)
    if graph.graph_backend != nothing
        graph.graph_backend.update_backend = true
    end
    return graph.is_dirty = true
end

#################
#Subgraphs
#################
"""
    add_subgraph!(graph::OptiGraph, subgraph::OptiGraph)::OptiGraph

Add the sub-optigraph `subgraph` to the higher level optigraph `graph`. Returns the original `graph`
"""
function add_subgraph!(graph::OptiGraph, subgraph::OptiGraph)
    push!(graph.subgraphs, subgraph)
    _flag_graph_backend!(graph)
    return graph
end

"""
    subgraphs(optigraph::OptiGraph)::Vector{OptiGraph}

Retrieve the local subgraphs of `optigraph`.
"""
subgraphs(optigraph::OptiGraph) = OptiGraph[subgraph for subgraph in optigraph.subgraphs]
@deprecate getsubgraphs subgraphs
"""
    subgraph(graph::OptiGraph, idx::Int64)

Retrieve the the subgraph in `graph` at index `idx`.
"""
subgraph(graph::OptiGraph, idx::Int64) = graph.subgraphs[idx]
@deprecate getsubgraph subgraph
"""
    all_subgraphs(graph::OptiGraph)::Vector{OptiGraph}

Retrieve all of the contained subgraphs of `graph`, including nested subgraphs. The order of the subgraphs in
the returned vector starts with the local subgraphs in `optigraph` and then appends the nested subgraphs for each local subgraph.
"""
function all_subgraphs(graph::OptiGraph)
    subgraphs = graph.subgraphs
    for subgraph in subgraphs
        subgraphs = [subgraphs; all_subgraphs(subgraph)]
    end
    return subgraphs
end

"""
    subgraph_by_index(graph::OptiGraph, index::Int64)::OptiGraph

Recursively search optigraph `graph` for the subngraph at `index` by traversing subgraphs.
Note that the subgraph is not unique to the index. Since the search is depth-first, the subgraph
returned may be different if the overall `graph` structure changes.
"""
subgraph_by_index(graph::OptiGraph, index::Int64) = all_subgraphs(graph)[index]

"""
    num_subgraphs(graph::OptiGraph)::Int64

Retrieve the number of local subgraphs in `graph`.
"""
num_subgraphs(optigraph::OptiGraph) = length(optigraph.subgraphs)

"""
    num_all_subgraphs(graph::OptiGraph)::Int64

Retrieve the number of subgraphs in `graph` including nested subgraphs.
"""
num_all_subgraphs(optigraph::OptiGraph) = length(all_subgraphs(optigraph))

"""
    has_subgraphs(graph::OptiGraph)::Bool

Check whether `graph` contains subgraphs.
 """
has_subgraphs(graph::OptiGraph) = !(isempty(graph.subgraphs))

#################
#OptiNodes
#################
"""
    add_node!(graph::OptiGraph)::OptiNode

Create a new `OptiNode` and add it to `graph`. Returns the added optinode.

    add_node!(graph::OptiGraph, m::JuMP.Model)::OptiNode

Add a new optinode to `graph` and set its model to the `JuMP.Model` `m`.

    add_node!(graph::OptiGraph, optinode::OptiNode)::OptiNode

Add the existing `optinode` (Created with `OptiNode()`) to the optigraph `graph`.
"""
function add_node!(graph::OptiGraph; label::String="n$(length(graph.optinodes) + 1)")
    optinode = OptiNode()
    optinode.label = label
    add_node!(graph, optinode)
    return optinode
end

function add_node!(graph::OptiGraph, m::JuMP.Model)
    optinode = add_node!(graph)
    set_model(optinode, m)
    return optinode
end

function add_node!(graph::OptiGraph, optinode::OptiNode)
    push!(graph.optinodes, optinode)
    graph.node_idx_map[optinode] = length(graph.optinodes)
    _flag_graph_backend!(graph)
    return optinode
end

function add_node!(graph::OptiGraph, m::JuMP.Model, label::String)
    optinode = add_node!(graph)
    set_model(optinode, m)
    optinode.label = label
    return optinode
end

"""
    optinodes(graph::OptiGraph)::Vector{OptiNode}

Retrieve the optinodes in `graph`. Note that this returns the local optinodes contained
directly in `graph` and excludes nodes contained in subgraphs of `graph`.
"""
optinodes(graph::OptiGraph) = graph.optinodes

"""
    optinode(graph::OptiGraph, index::Int64)

Retrieve the local optinode in `graph` at `index`. This does not retrieve nodes in subgraphs.
"""
optinode(graph::OptiGraph, index::Int64) = graph.optinodes[index]
@deprecate getnode optinode
@deprecate getnodes optinodes

"""
    optinode_by_index(graph::OptiGraph, index::Int64)::OptiNode

Recursively search optigraph `graph` for the optinode at `index` by traversing subgraphs.
Note that the optinode is not unique to the index. Since the search is depth-first, the optinode
returned may be different if the subgraph structure changes.
"""
function optinode_by_index(graph::OptiGraph, index::Int64)
    nodes = all_nodes(graph)
    return nodes[index]
end
@deprecate(all_node, optinode_by_index)

"""
    all_nodes(graph::OptiGraph)::Vector{OptiNode}

Recursively collect all optinodes in `graph` by traversing each of its subgraphs.
"""
function all_nodes(graph::OptiGraph)
    nodes = graph.optinodes
    for subgraph in graph.subgraphs
        nodes = [nodes; all_nodes(subgraph)]
    end
    return nodes
end

"""
    num_nodes(graph::OptiGraph)::Int64

Return the number of local nodes in `graph`.
"""
num_nodes(graph::OptiGraph) = length(graph.optinodes)

"""
    num_all_nodes(graph::OptiGraph)::Int64

Return the total number of nodes in `graph` including subgraphs.
"""
function num_all_nodes(graph::OptiGraph)
    n_nodes = sum(num_nodes.(all_subgraphs(graph)))
    n_nodes += num_nodes(graph)
    return n_nodes
end

"""
    Base.getindex(graph::OptiGraph, node::OptiNode)

Retrieve the index of the optinode `node` in `graph`.
"""
function Base.getindex(graph::OptiGraph, node::OptiNode)
    return graph.node_idx_map[node]
end

"""
    Base.getindex(graph::OptiGraph, index::Int64)

Retrieve the node at `index` in `graph`.
"""
Base.getindex(graph::OptiGraph, index::Int64) = optinode(graph, index)

###################################################
#OptiEdges
###################################################
"""
    add_optiedge!(graph::OptiGraph, optinodes::Vector{OptiNode})::OptiEdge

Add an optiedge to optigraph `graph` that connects `optinodes`. If edge already exists, return it.
"""
function add_optiedge!(graph::OptiGraph, nodes::Vector{OptiNode})
    key = Set(nodes)
    if haskey(graph.optiedge_map, key)
        edge = graph.optiedge_map[key]
    else
        n_links = length(graph.optiedges)
        idx = n_links + 1
        edge = OptiEdge(nodes)
        push!(graph.optiedges, edge)
        graph.optiedge_map[edge.nodes] = edge
        graph.edge_idx_map[edge] = idx
        _flag_graph_backend!(graph)
    end
    return edge
end

"""
    optiedges(graph::OptiGraph)::Vector{OptiEdge}

Retrieve the local optiedges in `graph`.
"""
optiedges(graph::OptiGraph) = graph.optiedges
@deprecate getedges optiedges

"""
    optiedge(graph::OptiGraph, index::Int64)

Retrieve the local optiedge in `graph` at `index`

    optiedge(graph::OptiGraph, nodes::OrderedSet{OptiNode})

Retrieve the optiedge in `graph` that connects the optinodes in the OrderedSet of `nodes`.

    optiedge(graph::OptiGraph, nodes::OptiNode...)

Retrieve the optiedge in `graph` that connects `nodes`.
"""
optiedge(graph::OptiGraph, index::Int64) = graph.optiedges[index]
optiedge(graph::OptiGraph, nodes::Set{OptiNode}) = graph.optiedge_map[nodes]
function optiedge(graph::OptiGraph, nodes::OptiNode...)
    s = Set(collect(nodes))
    return optiedge(graph, s)
end
@deprecate getedge optiedge

"""
    all_edges(graph::OptiGraph)::Vector{OptiEdge}

Recursively collect all optiedges in `graph` by traversing each of its subgraphs.
"""
function all_edges(graph::OptiGraph)
    edges = graph.optiedges
    for subgraph in graph.subgraphs
        edges = [edges; all_edges(subgraph)]
    end
    return edges
end

"""
    optiedge_by_index(graph::OptiGraph, index::Int64)::OptiEdge

Recursively search optigraph `graph` for the edge at `index` by traversing subgraphs.
Note that the edge is not unique to the index. Since the search is depth-first, the optiedge
returned may be different if the subgraph structure changes.
"""
function optiedge_by_index(graph::OptiGraph, index::Int64)
    edges = all_edges(graph)
    return edges[index]
end

"""
    num_edges(graph::OptiGraph)::Int64

Return the number of local edges in `graph`
"""
num_edges(graph::OptiGraph) = length(graph.optiedges)
@deprecate num_optiedges num_edges

"""
    num_all_edges(graph::OptiGraph)

Return the total number of optiedges in `graph` including subgraphs.
"""
function num_all_edges(graph::OptiGraph)
    n_link_edges = sum(num_edges.(all_subgraphs(graph)))
    n_link_edges += num_edges(graph)
    return n_link_edges
end
@deprecate num_all_optiedges num_all_edges
"""
    Base.getindex(graph::OptiGraph, optiedge::OptiEdge)::Int64

Retrieve the index of the `optiedge` in `graph`.
"""
Base.getindex(graph::OptiGraph, optiedge::OptiEdge) = graph.edge_idx_map[optiedge]

########################################################
# OptiGraph Model Interaction
########################################################
"""
    has_objective(graph::OptiGraph)::Bool

Check whether optigraph `graph` has an affine or quadratic objective function set.
"""
function has_objective(graph::OptiGraph)
    return graph.objective_function != zero(JuMP.AffExpr) &&
           graph.objective_function != zero(JuMP.QuadExpr)
end

"""
    has_node_objective(graph::OptiGraph)::Bool

Check whether any optinode in `graph` has an objective function.
"""
has_node_objective(graph::OptiGraph) = any(has_objective.(all_nodes(graph)))

"""
    has_node_quad_objective(graph::OptiGraph)::Bool

Check whether any optinode in `graph` has a quadratic objective function.
"""
function has_node_quad_objective(graph::OptiGraph)
    return any((node) -> isa(objective_function(node), JuMP.QuadExpr), all_nodes(graph))
end
@deprecate has_quad_objective has_node_quad_objective

"""
    has_nlp_data(graph::OptiGraph)::Bool

Check whether any optinode in `graph` has nlp data
"""
function has_nlp_data(graph::OptiGraph)
    return any(node -> (JuMP.nonlinear_model(node) !== nothing), all_nodes(graph))
end

"""
    has_nl_objective(graph::OptiGraph)::Bool

Check whether any optinode in `graph` has a nonlinear objective function.
"""
function has_nl_objective(graph::OptiGraph)
    for node in all_nodes(graph)
        if has_nl_objective(node)
            return true
        end
    end
    return false
end

"""
    JuMP.object_dictionary(graph::OptiGraph)

Retrieve the object dictionary of optigraph `graph`
"""
JuMP.object_dictionary(graph::OptiGraph) = graph.obj_dict

"""
    JuMP.all_variables(graph::OptiGraph)::Vector{JuMP.VariableRef}

Retrieve a list of all variables in optigraph `graph.`
"""
function JuMP.all_variables(graph::OptiGraph)
    vars = vcat([JuMP.all_variables(node) for node in all_nodes(graph)]...)
    return vars
end

"""
    JuMP.num_variables(graph::OptiGraph)::Int64

Retrieve the number of local node variables in `graph`. Does not include variables in subgraphs.
"""
function JuMP.num_variables(graph::OptiGraph)
    n_node_variables = sum(JuMP.num_variables.(optinodes(graph)))
    return n_node_variables
end

"""
    JuMP.num_all_variables(graph::OptiGraph)

Retrieve the number of total variables in `graph`. Includes variables in subgraphs.
"""
function num_all_variables(graph::OptiGraph)
    n_node_variables = sum(JuMP.num_variables.(all_nodes(graph)))
    return n_node_variables
end

"""
    JuMP.value(graph::OptiGraph, vref::VariableRef)

Get the variable value of `vref` on the optigraph `graph`. This value corresponds to
the optinode variable value obtained by solving `graph` which contains said optinode.
"""
function JuMP.value(graph::OptiGraph, var::JuMP.VariableRef)
    node_pointer = JuMP.backend(var.model).result_location[graph.id]
    var_idx = node_pointer.node_to_optimizer_map[index(var)]
    # return MOI.get(backend(graph).optimizer, MOI.VariablePrimal(), var_idx)
    return MOI.get(node_pointer, MOI.VariablePrimal(), var_idx)
end

"""
    JuMP.list_of_constraint_types(graph::OptiGraph)

Retrieve a list of the constraint types in optigraph `graph`
"""
function JuMP.list_of_constraint_types(graph::OptiGraph)
    return unique(vcat(JuMP.list_of_constraint_types.(all_nodes(graph))...))
end

"""
    JuMP.all_constraints(graph::OptiGraph, F::DataType, S::DataType)

Retrieve a list of contraints with function type `F` and set `S` in optigraph `graph`
"""
function JuMP.all_constraints(graph::OptiGraph, F::DataType, S::DataType)
    return vcat(JuMP.all_constraints.(all_nodes(graph), Ref(F), Ref(S))...)
end
JuMP.show_constraints_summary(::IOContext, m::OptiGraph) = ""
JuMP.show_backend_summary(::IOContext, m::OptiGraph) = ""

function num_all_constraints(graph::OptiGraph)
    n_node_constraints = sum(JuMP.num_constraints.(all_nodes(graph)))
    return n_node_constraints
end

"""
    JuMP.num_constraints(graph::OptiGraph)

Retrieve the number of local node constraints in `graph`. Does not include constraints in subgraphs.
"""
function JuMP.num_constraints(graph::OptiGraph)
    n_node_constraints = sum(JuMP.num_constraints.(optinodes(graph)))
    return n_node_constraints
end

"""
    linkconstraints(graph::OptiGraph)::Vector{LinkConstraintRef}

Retrieve the local linking constraints in `graph`. Returns a vector of the linking constraints.
"""
function linkconstraints(graph::OptiGraph)
    links = LinkConstraintRef[]
    for edge in graph.optiedges
        append!(links, edge.linkrefs)
    end
    return links
end

"""
    all_linkconstraints(graph::OptiGraph)::Vector{LinkConstraintRef}

Recursively collect all linkconstraints in `graph` by traversing each of its subgraphs.
"""
function all_linkconstraints(graph::OptiGraph)
    links = LinkConstraintRef[]
    for subgraph in all_subgraphs(graph)
        append!(links, linkconstraints(subgraph))
    end
    append!(links, linkconstraints(graph))
    return links
end

"""
    num_linkconstraints(graph::OptiGraph)::Int64

Retrieve the number of local linking constraints in `graph`. Does not include linkconstraints in subgraphs.
"""
num_linkconstraints(graph::OptiGraph) = sum(num_linkconstraints.(graph.optiedges))

"""
    num_all_linkconstraints(graph::OptiGraph)::Int64

Retrieve the total number linkconstraints in `graph`. Includes linkconstraints in subgraphs.
"""
num_all_linkconstraints(graph::OptiGraph) = length(all_linkconstraints(graph))

####################################
# Objective
###################################
"""
    JuMP.objective_function(graph::OptiGraph)::MOI.OptimizationSense

Retrieve the current graph objective sense.
"""
JuMP.objective_sense(graph::OptiGraph) = graph.objective_sense

"""
    JuMP.set_objective_sense(graph::OptiGraph, sense::MOI.OptimizationSense)

Set the current graph objective sense to `sense`.
"""
function JuMP.set_objective_sense(graph::OptiGraph, sense::MOI.OptimizationSense)
    return graph.objective_sense = sense
end

"""
    JuMP.objective_function(graph::OptiGraph)

Retrieve the current graph objective function.
"""
function JuMP.objective_function(graph::OptiGraph)
    if has_objective(graph)
        return graph.objective_function
    elseif has_node_objective(graph) #check for node objective
        obj = 0
        for node in all_nodes(graph)
            scl = JuMP.objective_sense(node) == MOI.MAX_SENSE ? -1 : 1
            obj += scl * objective_function(node)
        end
        return obj
    else #it's just 0
        return graph.objective_function
    end
end

"""
    JuMP.set_objective_function(graph::OptiGraph, x::JuMP.VariableRef)

Set a single variable objective function on optigraph `graph`

    JuMP.set_objective_function(graph::OptiGraph, expr::JuMP.GenericAffExpr)

Set an affine objective function on optigraph `graph`

    JuMP.set_objective_function(graph::OptiGraph, expr::JuMP.GenericQuadExpr)

Set a quadratic objective function on optigraph `graph`
"""
function JuMP.set_objective_function(graph::OptiGraph, x::JuMP.VariableRef)
    x_affine = convert(JuMP.AffExpr, x)
    return JuMP.set_objective_function(graph, x_affine)
end

function JuMP.set_objective_function(graph::OptiGraph, expr::JuMP.GenericAffExpr)
    graph.objective_function = expr
    return nothing
end

function JuMP.set_objective_function(graph::OptiGraph, expr::JuMP.GenericQuadExpr)
    graph.objective_function = expr
    return nothing
end

function set_node_objective_functions(graph::OptiGraph)
    _set_node_objective_functions(graph, objective_function(graph))
    return nothing
end

function _set_node_objective_functions(graph::OptiGraph, expr::JuMP.GenericAffExpr)
    node_expressions = Dict()
    for node in all_nodes(graph)
        node_expressions[node] = JuMP.AffExpr()
    end
    for (coef, term) in JuMP.linear_terms(expr)
        node = optinode(term)
        JuMP.add_to_expression!(node_expressions[node], coef, term)
    end
    for node in all_nodes(graph)
        JuMP.set_objective_function(node, node_expressions[node])
    end
    return nothing
end

function _set_node_objective_functions(graph::OptiGraph, expr::JuMP.GenericQuadExpr)
    node_expressions = Dict()
    for node in all_nodes(graph)
        node_expressions[node] = JuMP.QuadExpr()
    end
    for (coef, term1, term2) in JuMP.quad_terms(expr)
        @assert optinode(term1) == optinode(term2)
        node = optinode(term1)
        JuMP.add_to_expression!(node_expressions[node], coef, term1, term2)
    end
    for (coef, term) in JuMP.linear_terms(expr)
        node = optinode(term)
        JuMP.add_to_expression!(node_expressions[node], coef, term)
    end
    for node in all_nodes(graph)
        JuMP.set_objective_function(node, node_expressions[node])
    end
    return nothing
end

"""
    JuMP.set_objective(graph::OptiGraph, sense::MOI.OptimizationSense, func::JuMP.AbstractJuMPScalar)

Set the objective of `graph` to the optimization `sense` and `func`.
"""
function JuMP.set_objective(
    graph::OptiGraph, sense::MOI.OptimizationSense, func::JuMP.AbstractJuMPScalar
)
    JuMP.set_objective_sense(graph, sense)
    return JuMP.set_objective_function(graph, func)
end

"""
    JuMP.objective_function_type(graph::OptiGraph)

Retrieve the objective function type of optigraph `graph`.
"""
JuMP.objective_function_type(graph::OptiGraph) = typeof(objective_function(graph))

#NOTE: Plasmo stores the objective expression on the optigraph
function JuMP.set_objective_coefficient(
    graph::OptiGraph, variable::JuMP.VariableRef, coefficient::Real
)
    if has_nl_objective(graph)
        error("A nonlinear objective is already set in the model")
    end
    coeff = convert(Float64, coefficient)::Float64
    current_obj = objective_function(graph)
    obj_fct_type = objective_function_type(graph)
    if obj_fct_type == VariableRef
        if index(current_obj) == index(variable)
            set_objective_function(graph, coeff * variable)
        else
            set_objective_function(graph, add_to_expression!(coeff * variable, current_obj))
        end
        #TODO: add new variables
    elseif obj_fct_type == AffExpr
        current_obj.terms[variable] = coefficient
    elseif obj_fct_type == QuadExpr
        current_obj.aff.terms[variable] = coefficient
    else
        error("Objective function type not supported: $(obj_fct_type)")
    end
end

"""
    JuMP.objective_value(graph::OptiGraph)

Retrieve the current objective value on optigraph `graph`.
"""
function JuMP.objective_value(graph::OptiGraph)
    return MOI.get(backend(graph), MOI.ObjectiveValue())
end

function optinodes(expr::JuMP.GenericAffExpr)
    nodes = OptiNode[]
    for (coef, term) in JuMP.linear_terms(expr)
        node = optinode(term)
        push!(nodes, node)
    end
    return unique(nodes)
end

function optinodes(expr::JuMP.GenericQuadExpr)
    nodes = OptiNode[]
    for (coef, term1, term2) in JuMP.quad_terms(expr)
        @assert optinode(term1) == optinode(term2)
        node = optinode(term1)
        push!(nodes, node)
    end
    for (coef, term) in JuMP.linear_terms(expr)
        node = optinode(term)
        push!(nodes, node)
    end
    return unique(nodes)
end

#####################################################
#  Link Constraints
#  A linear constraint between optinodes.  Link constraints can be equality or inequality.
#####################################################
function JuMP.add_constraint(
    graph::OptiGraph, con::JuMP.AbstractConstraint, name::String=""
)
    return error(
        "Cannot add constraint $con. An OptiGraph currently only supports Scalar LinkConstraints",
    )
end

function JuMP.add_constraint(
    graph::OptiGraph,
    con::JuMP.ScalarConstraint,
    name::String="";
    attached_node=optinode(collect(keys(con.func.terms))[1]),
)
    cref = add_link_constraint(graph, con, name; attached_node=attached_node)
    return cref
end

JuMP._valid_model(m::OptiEdge, name) = nothing
function JuMP.add_constraint(
    optiedge::OptiEdge,
    con::JuMP.ScalarConstraint,
    name::String="";
    attached_node=optinode(collect(keys(con.func.terms))[1]),
)
    cref = add_link_constraint(optiedge, con, name; attached_node=attached_node)
    return cref
end

#Create optiedge and add linkconstraint
function add_link_constraint(
    graph::OptiGraph, con::JuMP.ScalarConstraint, name::String=""; attached_node=nothing
)
    nodes = optinodes(con)
    optiedge = add_optiedge!(graph, nodes)
    cref = JuMP.add_constraint(optiedge, con, name; attached_node=attached_node)
    return cref
end

#Add linkconstraint directly to optiedge
function add_link_constraint(
    optiedge::OptiEdge, con::JuMP.ScalarConstraint, name::String=""; attached_node=nothing
)
    typeof(con.set) in [
        MOI.Interval{Float64},
        MOI.LessThan{Float64},
        MOI.GreaterThan{Float64},
        MOI.EqualTo{Float64},
    ] || error("Unsupported link constraint set of type $(con.set)")

    link_con = LinkConstraint(con)    #Convert ScalarConstraint to a LinkConstraint
    link_con.attached_node = attached_node

    nodes = optinodes(link_con)
    @assert issubset(nodes, optiedge.nodes)

    linkconstraint_index = length(optiedge.linkconstraints) + 1
    cref = LinkConstraintRef(linkconstraint_index, optiedge)
    JuMP.set_name(cref, name)
    push!(optiedge.linkrefs, cref)
    optiedge.linkconstraints[linkconstraint_index] = link_con

    #Add partial linkconstraint to nodes
    node_partial_indices = Dict(
        node => length(node.partial_linkconstraints) + 1 for node in optiedge.nodes
    )
    for (var, coeff) in link_con.func.terms
        node = optinode(var)
        index = node_partial_indices[node] #index of current linkconstraint for this node
        _add_to_partial_linkconstraint!(
            node, var, coeff, link_con.func.constant, link_con.set, index
        )
    end

    return cref
end

#Add partial link constraint to supporting optinodes
function _add_to_partial_linkconstraint!(
    node::OptiNode,
    var::JuMP.VariableRef,
    coeff::Number,
    constant::Float64,
    set::MOI.AbstractScalarSet,
    index::Int64,
)
    @assert optinode(var) == node
    #multiple variables might be on the same node, so check here
    if haskey(node.partial_linkconstraints, index)
        linkcon = node.partial_linkconstraints[index]
        JuMP.add_to_expression!(linkcon.func, coeff, var)
        constant == linkcon.func.constant || error(
            "Found a Link Constraint constant mismatch when adding partial constraint to optinode",
        )
        set == linkcon.set || error(
            "Found a Link Constraint set mismatch when adding partial constraint to optinode",
        )
    else #create a new partial constraint
        node_func = JuMP.GenericAffExpr{Float64,JuMP.VariableRef}()
        node_func.terms[var] = coeff
        node_func.constant = constant
        linkcon = LinkConstraint(node_func, set, node)
        node.partial_linkconstraints[index] = linkcon
    end
end

function JuMP.add_bridge(graph::OptiGraph, BridgeType::Type{<:MOI.Bridges.AbstractBridge})
    push!(graph.bridge_types, BridgeType)
    #_moi_add_bridge(JuMP.backend(model), BridgeType)
    return nothing
end

"""
    JuMP.dual(graph::OptiGraph, linkref::LinkConstraintRef)

Retrieve the dual value of `linkref` on optigraph `graph`.
"""
function JuMP.dual(graph::OptiGraph, linkref::LinkConstraintRef)
    optiedge = JuMP.owner_model(linkref)
    edge_pointer = optiedge.backend.optimizers[graph.id]
    dual_value = MOI.get(edge_pointer, MOI.ConstraintDual(), linkref)
    return dual_value
end

# set start value for a graph backend
# NOTE: currently requires assembling the graph backend first
function JuMP.set_start_value(graph::OptiGraph, variable::JuMP.VariableRef, value::Number)
    if MOIU.state(backend(graph)) == MOIU.NO_OPTIMIZER
        error("Cannot set start value for optigraph with no optimizer")
    end
    # TODO: decide whether we really need to call optimize! first, or just build the graph backend
    if MOI.get(JuMP.backend(graph), MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED
        error(
            "Start values can only be set for an optigraph optimizer after the initial `optimize!` has been called.  Use `set_start_value(var::JuMP.VariableRef,value::Number)` to set a start value before `optimize!`",
        )
    end
    node_pointer = JuMP.backend(optinode(variable)).optimizers[graph.id]
    var_idx = node_pointer.node_to_optimizer_map[index(variable)]

    # NOTE: I think this should also update the graph backend variable attribute
    # This would hit the fallback model if needed
    MOI.set(graph.moi_backend.model_cache, MOI.VariablePrimalStart(), var_idx, value)
    return MOI.set(node_pointer, MOI.VariablePrimalStart(), var_idx, value)
end

# MAJOR TODO: query the correct place for start values. We need to correctly support variable optimizer attributes through the node pointers
# Need to make sure that setting attributes like name hits the model_cache instead
# we can set the primal_start on Ipopt, but we need to fall back to the correct model_cache to retrieve it
# node pointer should hit GraphBackend, not the GraphBackend optimizer
function JuMP.start_value(graph::OptiGraph, variable::JuMP.VariableRef)
    # decide whether we check the graph backend model_cache, or the node itself, or the node model cache?
    node_pointer = JuMP.backend(variable.model).result_location[graph.id]
    var_idx = node_pointer.node_to_optimizer_map[index(variable)]
    return MOI.get(backend(graph), MOI.VariablePrimalStart(), var_idx)
end

function JuMP.set_attribute(
    graph::OptiGraph,
    attr::MOI.AbstractModelAttribute,
    value
)
    MOI.set(graph, attr, value)
    return
end

function JuMP.solver_name(graph::OptiGraph)
    return MOI.get(graph.moi_backend, MOI.SolverName())
end

"""
    JuMP.termination_status(graph::OptiGraph)

Retrieve the current termination status of optigraph `graph`.
"""
function JuMP.termination_status(graph::OptiGraph)
    return MOI.get(graph.moi_backend, MOI.TerminationStatus())
end

function JuMP.primal_status(graph::OptiGraph)
    return MOI.get(graph.moi_backend, MOI.PrimalStatus())
end

function JuMP.dual_status(graph::OptiGraph)
    return MOI.get(graph.moi_backend, MOI.DualStatus())
end

function JuMP.callback_value(cb_data, x::GenericVariableRef, graph::OptiGraph)
    return MOI.get(
        graph.moi_backend.optimizer,
        MOI.CallbackVariablePrimal(cb_data),
        index(x),
    )
end

function JuMP.callback_node_status(cb_data, graph::OptiGraph)
    return MOI.get(graph.moi_backend.optimizer, MOI.CallbackNodeStatus(cb_data))
end

####################################
#Print Functions
####################################
function string(graph::OptiGraph)
    return @sprintf(
        """%16s %10s %20s
-------------------------------------------------------------------
%16s %5s %16s
%16s %5s %16s
%16s %5s %16s
%16s %5s %16s""",
        "OptiGraph:",
        "# elements",
        "(including subgraphs)",
        "OptiNodes:",
        num_nodes(graph),
        "($(num_all_nodes(graph)))",
        "OptiEdges:",
        num_edges(graph),
        "($(num_all_edges(graph)))",
        "LinkConstraints:",
        num_linkconstraints(graph),
        "($(num_all_linkconstraints(graph)))",
        "sub-OptiGraphs:",
        num_subgraphs(graph),
        "($(num_all_subgraphs(graph)))"
    )
end

print(io::IO, graph::OptiGraph) = print(io, string(graph))
show(io::IO, graph::OptiGraph) = print(io, graph)

"""
    empty!(graph::OptiGraph) -> graph
Empty the optigraph, that is, remove all variables, constraints and model
attributes but not optimizer attributes. Always return the argument.
Note: removes extensions data.
"""
function Base.empty!(graph::OptiGraph)::OptiGraph
    #MOI.empty!(graph.moi_backend)
    graph.moi_backend = GraphBackend(graph)
    empty!(graph.obj_dict)
    empty!(graph.ext)

    graph.optinodes = Vector{OptiNode}()
    graph.optiedges = Vector{OptiEdge}()
    graph.node_idx_map = Dict{OptiNode,Int64}()
    graph.edge_idx_map = Dict{OptiEdge,Int64}()
    graph.subgraphs = Vector{AbstractOptiGraph}()

    graph.optiedge_map = OrderedDict{Set,OptiEdge}()

    #Objective
    graph.objective_sense = MOI.FEASIBILITY_SENSE
    graph.objective_function = zero(JuMP.GenericAffExpr{Float64,JuMP.AbstractVariableRef})

    return graph
end

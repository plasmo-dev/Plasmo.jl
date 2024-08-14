#  Copyright 2021, Jordan Jalving, Yankai Cao, Victor Zavala, and contributors
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at https://mozilla.org/MPL/2.0/.

function OptiGraph(; name::Symbol=Symbol(:g, gensym()))
    graph = OptiGraph(
        name,
        OrderedSet{OptiNode}(),
        OrderedSet{OptiEdge}(),
        OrderedSet{OptiGraph}(),
        OrderedDict{Set{OptiNode},OptiEdge}(),
        nothing,
        ElementData(OptiGraph),
        nothing,
        Dict{Symbol,Any}(),
        Dict{Symbol,Any}(),
        Set{Any}(),
        false,
    )

    # default is MOI backend
    graph.backend = GraphMOIBackend(graph)
    return graph
end

function Base.string(graph::OptiGraph)
    return @sprintf(
        """
        An OptiGraph
        %16s %9s %16s
        --------------------------------------------------
        %16s %9s %16s
        %16s %9s %16s
        %16s %9s %16s
        %16s %9s %16s
        %16s %9s %16s
        """,
        "$(name(graph))",
        "#local elements",
        "#total elements",
        "Nodes:",
        num_local_nodes(graph),
        num_nodes(graph),
        "Edges:",
        num_local_edges(graph),
        num_edges(graph),
        "Subgraphs:",
        num_local_subgraphs(graph),
        num_subgraphs(graph),
        "Variables:",
        num_local_variables(graph),
        num_variables(graph),
        "Constraints:",
        num_local_constraints(graph),
        num_constraints(graph)
    )
end
Base.print(io::IO, graph::OptiGraph) = Base.print(io, Base.string(graph))
Base.show(io::IO, graph::OptiGraph) = Base.print(io, graph)

"""
    Base.getindex(graph::OptiGraph, idx::Int)

Get the optinode at the given index.
"""
function Base.getindex(graph::OptiGraph, idx::Int)
    return collect(graph.optinodes)[idx]
end

function Base.getindex(graph::OptiGraph, range::UnitRange{Int})
    return collect(graph.optinodes)[range]
end

Base.broadcastable(graph::OptiGraph) = Ref(graph)

# TODO: parameterize on numerical precision like JuMP Models do
JuMP.value_type(::Type{OptiGraph}) = Float64

#
# Optigraph methods
#

"""
    graph_backend(graph::OptiGraph)

Return the intermediate backend used to map the optigraph to an optimizer. Plasmo.jl 
currently only supports a backend to MathOptInterface.jl optimizers, but future versions
intend to support GraphOptInterface.jl as a structured backend. 
"""
function graph_backend(graph::OptiGraph)
    return graph.backend
end

### Graph Index

"""
    graph_index(ref::RT) where {RT<:Union{NodeVariableRef,ConstraintRef}}

Return the the corresponding variable or constraint index corresponding to a reference.
"""
function graph_index(ref::RT) where {RT<:Union{NodeVariableRef,ConstraintRef}}
    return graph_index(graph_backend(JuMP.owner_model(ref)), ref)
end
function graph_index(
    graph::OptiGraph, ref::RT
) where {RT<:Union{NodeVariableRef,ConstraintRef}}
    return graph_index(graph_backend(graph), ref)
end

### Assemble OptiGraph

function _assemble_optigraph(nodes::Vector{<:OptiNode}, edges::Vector{<:OptiEdge})
    graph = OptiGraph()
    for node in nodes
        add_node(graph, node)
    end
    for edge in edges
        add_edge(graph, edge)
    end
    return graph
end

"""
    assemble_optigraph(nodes::Vector{<:OptiNode}, edges::Vector{OptiEdge})

Create a new optigraph from a collection of nodes and edges.
"""
function assemble_optigraph(
    nodes::Vector{<:OptiNode}, edges::Vector{<:OptiEdge}; name=nothing
)
    is_valid_optigraph(nodes, edges) ||
        error("The provided nodes and edges are not a valid optigraph. 
              All connected edge nodes must be provided in the node vector.")
    graph = _assemble_optigraph(nodes, edges)
    if name != nothing
        JuMP.set_name(graph, name)
    end
    return graph
end

function assemble_optigraph(node::OptiNode)
    graph = OptiGraph()
    add_node(graph, node)
    return graph
end

"""
    is_valid_optigraph(nodes::Vector{<:OptiNode}, edges::Vector{OptiEdge})

Check whether the given nodes and edges can create a valid optigraph.
"""
function is_valid_optigraph(nodes::Vector{<:OptiNode}, edges::Vector{<:OptiEdge})
    if length(edges) == 0
        return true
    end
    edge_nodes = union(all_nodes.(edges)...)
    return isempty(setdiff(edge_nodes, nodes)) ? true : false
end

### Manage OptiNodes

"""
    add_node(
        graph::OptiGraph; label=Symbol(graph.label, Symbol(".n"), length(graph.optinodes)+1
    )

Add a new optinode to `graph`. By default, the node label is set to be "n<i+1>" where "i" is 
the number of nodes in the graph.
"""
function add_node(
    graph::OptiGraph; label=Symbol(graph.label, Symbol(".n"), length(graph.optinodes) + 1)
)
    node_index = NodeIndex(gensym())
    node = OptiNode(Ref(graph), node_index, Ref(label))
    push!(graph.optinodes, node)
    add_node(graph_backend(graph), node)
    return node
end
@deprecate add_node! add_node

"""
    add_node(graph::OptiGraph, node::OptiNode)

Add an existing optinode (created in another optigraph) to `graph`. This copies model data 
from the other graph to the new graph.
"""
function add_node(graph::OptiGraph, node::OptiNode)
    node in all_nodes(graph) && error("Node already exists within graph")
    push!(graph.optinodes, node)
    add_node(graph_backend(graph), node)
    _track_node_in_graph(graph, node)
    return nothing
end

function _track_node_in_graph(graph::OptiGraph, node::OptiNode)
    source = source_graph(node)
    source_data = source.element_data
    if haskey(source_data.node_to_graphs, node)
        push!(source_data.node_to_graphs[node], graph)
    else
        source_data.node_to_graphs[node] = [graph]
    end
    return nothing
end

"""
    get_node(graph::OptiGraph, idx::Int)

Retrieve the optinode in `graph` at the given index.
"""
function get_node(graph::OptiGraph, idx::Int)
    return collect(graph.optinodes)[idx]
end

"""
    collect_nodes(jump_func::T where T <: JuMP.AbstractJuMPScalar)

Retrieve the optinodes contained in a JuMP expression.
"""
function collect_nodes(jump_func::T where {T<:JuMP.AbstractJuMPScalar})
    vars = _extract_variables(jump_func)
    nodes = JuMP.owner_model.(vars)
    return collect(nodes)
end

"""
    local_nodes(graph::OptiGraph)::Vector{<:OptiNode}

Retrieve the optinodes defined within the optigraph `graph`. This does 
not return nodes that exist in subgraphs.
"""
function local_nodes(graph::OptiGraph)
    return collect(graph.optinodes)
end

@deprecate get_nodes local_nodes

"""
    num_local_nodes(graph::OptiGraph)::Int

Return the number of local nodes in the optigraph `graph`.
"""
function num_local_nodes(graph::OptiGraph)
    return length(graph.optinodes)
end

"""
    all_nodes(graph::OptiGraph)::Vector{<:OptiNode}

Recursively collect all optinodes in `graph` by traversing each of its subgraphs.
"""
function all_nodes(graph::OptiGraph)
    nodes = collect(graph.optinodes)
    for subgraph in graph.subgraphs
        nodes = [nodes; all_nodes(subgraph)]
    end
    return nodes
end

"""
    num_nodes(graph::OptiGraph)::Int

Return the total number of nodes in `graph` by recursively checking subgraphs.
"""
function num_nodes(graph::OptiGraph)
    n_nodes = num_local_nodes(graph)
    for subgraph in graph.subgraphs
        n_nodes += num_nodes(subgraph)
    end
    return n_nodes
end

### Manage OptiEdges

"""
    add_edge(
        graph::OptiGraph,
        nodes::OptiNode...;
        label=Symbol(graph.label, Symbol(".e"), length(graph.optiedges) + 1),
    )

Add a new optiedge to `graph` that connects `nodes`. By default, the edge label is set to 
be "e<i+1>" where "i" is the number of edges in the graph.
"""
function add_edge(
    graph::OptiGraph,
    nodes::OptiNode...;
    label=Symbol(graph.label, Symbol(".e"), length(graph.optiedges) + 1),
)
    if has_edge(graph, Set(nodes))
        edge = get_edge(graph, Set(nodes))
    else
        edge = OptiEdge{typeof(graph)}(Ref(graph), label, OrderedSet(collect(nodes)))
        push!(graph.optiedges, edge)
        graph.optiedge_map[Set(collect(nodes))] = edge
        add_edge(graph_backend(graph), edge)
    end
    return edge
end

"""
    add_edge(graph::OptiGraph, edge::OptiEdge)

Add an existing optiedge (created in another optigraph) to `graph`. This copies model data 
from the other graph to the new graph.
"""
function add_edge(graph::OptiGraph, edge::OptiEdge)
    edge in all_edges(graph) && error("Cannot add the same edge to a graph multiple times")
    push!(graph.optiedges, edge)
    add_edge(graph_backend(graph), edge)
    _track_edge_in_graph(graph, edge)
    return nothing
end

function _track_edge_in_graph(graph::OptiGraph, edge::OptiEdge)
    source = source_graph(edge)
    source_data = source.element_data
    if haskey(source_data.edge_to_graphs, edge)
        push!(source_data.edge_to_graphs[edge], graph)
    else
        source_data.edge_to_graphs[edge] = [graph]
    end
    return nothing
end

"""
    has_edge(graph::OptiGraph, nodes::Set{<:OptiNode})

Return whether an edge that connects `nodes` exists in the graph.
"""
function has_edge(graph::OptiGraph, nodes::Set{<:OptiNode})
    if haskey(graph.optiedge_map, nodes)
        return true
    else
        return false
    end
end

"""
    get_edge(graph::OptiGraph, nodes::Set{<:OptiNode})

Retrieve the optiedge in `graph`. that connects `nodes`.
"""
function get_edge(graph::OptiGraph, nodes::Set{<:OptiNode})
    return graph.optiedge_map[nodes]
end

"""
    get_edge(graph::OptiGraph, nodes::OptiNode...)

Convenience method. Retrieve the optiedge in `graph` that connects `nodes`.
"""
function get_edge(graph::OptiGraph, nodes::OptiNode...)
    return get_edge(graph, Set(nodes))
end

"""
    get_edge_by_index(graph::OptiGraph, idx::Int64)

Retrieve the optiedge in `graph` that corresponds to the given index.
"""
function get_edge_by_index(graph::OptiGraph, idx::Int64)
    return collect(graph.optiedges)[idx]
end

"""
    local_edges(graph::OptiGraph)

Retrieve the edges that exists in `graph`. Does not return edges that exist in subgraphs.
"""
function local_edges(graph::OptiGraph)
    return collect(graph.optiedges)
end
@deprecate get_edges local_edges

"""
    num_local_edges(graph::OptiGraph)::Int

Return the number of local edges in the optigraph `graph`.
"""
function num_local_edges(graph::OptiGraph)
    return length(graph.optiedges)
end

"""
    all_edges(graph::OptiGraph)::Vector{<:OptiNode}

Recursively collect all optiedges in `graph` by traversing each of its subgraphs.
"""
function all_edges(graph::OptiGraph)
    edges = collect(graph.optiedges)
    for subgraph in graph.subgraphs
        edges = [edges; collect(all_edges(subgraph))]
    end
    return edges
end

"""
    num_edges(graph::OptiGraph)::Int

Return the total number of nodes in `graph` by recursively checking subgraphs.
"""
function num_edges(graph::OptiGraph)
    n_edges = num_local_edges(graph)
    for subgraph in graph.subgraphs
        n_edges += num_edges(subgraph)
    end
    return n_edges
end

"""
    num_local_elements(graph::OptiGraph)

Retrieve the number of local elements (nodes and edges) in `graph`. Does not include
elements in subgraphs.
"""
function num_local_elements(graph::OptiGraph)
    return num_local_nodes(graph) + num_local_edges(graph)
end

"""
    num_elements(graph::OptiGraph)

Retrieve the total number of local elements in `graph`. Includes elements in subgraphs.
"""
function num_elements(graph::OptiGraph)
    return num_nodes(graph) + num_edges(graph)
end

"""
    local_elements(graph::OptiGraph)

Retrieve the local elements (nodes and edges) in `graph`. Does not include elements in 
subgraphs.
"""
function local_elements(graph::OptiGraph)
    return [local_nodes(graph); local_edges(graph)]
end

"""
    local_elements(graph::OptiGraph)

Retrieve all elements (nodes and edges) in `graph`. Includes elements in subgraphs.
"""
function all_elements(graph::OptiGraph)
    return [all_nodes(graph); all_edges(graph)]
end

### Manage subgraphs

"""
    add_subgraph(graph::OptiGraph; name::Symbol=Symbol(:sg,gensym()))

Create and add a new subgraph to the optigraph `graph`.
"""
function add_subgraph(graph::OptiGraph; name::Symbol=Symbol(:sg, gensym()))
    subgraph = OptiGraph(; name=name)
    subgraph.parent_graph = graph
    push!(graph.subgraphs, subgraph)
    return subgraph
end

"""
    add_subgraph(graph::OptiGraph; name::Symbol=Symbol(:sg,gensym()))

Add an existing subgraph to an optigraph. The subgraph cannot already be part of another
optigraph. It also should not have nodes that already exist in the optigraph.
"""
function add_subgraph(graph::OptiGraph, subgraph::OptiGraph)
    subgraph.parent_graph == nothing || error("Cannot add subgraph to multiple graphs")
    subgraph.parent_graph = graph
    push!(graph.subgraphs, subgraph)
    return subgraph
end

@deprecate add_subgraph! add_subgraph

"""
    traverse_parents(graph::OptiGraph)

Return all the parents of the given `graph` if it has any. Can be used to determine how deep
the graph is located with another optigraph. 
"""
function traverse_parents(graph::OptiGraph)
    parents = OptiGraph[]
    if graph.parent_graph != nothing
        push!(parents, graph.parent_graph)
        append!(parents, traverse_parents(graph.parent_graph))
    end
    return parents
end

"""
    local_subgraphs(graph::OptiGraph)::Vector{OptiGraph}

Retrieve the local subgraphs of `graph`.
"""
function local_subgraphs(graph::OptiGraph)
    return collect(graph.subgraphs)
end
@deprecate getsubgraphs local_subgraphs

"""
    num_local_subgraphs(graph::OptiGraph)::Int

Retrieve the number of local subgraphs in `graph`. Does not include graph in subgraphs.
"""
function num_local_subgraphs(graph::OptiGraph)
    return length(graph.subgraphs)
end

"""
    all_subgraphs(graph::OptiGraph)::Vector{OptiGraph}

Retrieve all subgraphs of `graph`. Includes subgraphs within other subgraphs.
"""
function all_subgraphs(graph::OptiGraph)
    subs = collect(graph.subgraphs)
    for subgraph in graph.subgraphs
        subs = [subs; all_subgraphs(subgraph)]
    end
    return subs
end

"""
    num_subgraphs(graph::OptiGraph)::Int

Retrieve the total number of subgraphs in `graph`. Include subgraphs within subgraphs.
"""
function num_subgraphs(graph::OptiGraph)
    n_subs = num_local_subgraphs(graph)
    for subgraph in graph.subgraphs
        n_subs += num_local_subgraphs(subgraph)
    end
    return n_subs
end

### Link Constraints

"""
    num_local_link_constraints(
        graph::OptiGraph,
        func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
        set_type::Type{<:MOI.AbstractSet},
    )

Retrieve the number of local linking constraints with function `func_type` and set 
`set_type` in `graph`. Does not include linking constraints in subgraphs.
"""
function num_local_link_constraints(
    graph::OptiGraph,
    func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
    set_type::Type{<:MOI.AbstractSet},
)
    return sum(JuMP.num_constraints.(local_edges(graph), Ref(func_type), Ref(set_type)))
end

"""
    num_local_link_constraints(graph::OptiGraph)

Retrieve the number of local linking constraints (all constraint types) in `graph`. 
Does not include linking constraints in subgraphs.
"""
function num_local_link_constraints(graph::OptiGraph)
    return sum(JuMP.num_constraints.(local_edges(graph)))
end

"""
    num_link_constraints(
        graph::OptiGraph,
        func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
        set_type::Type{<:MOI.AbstractSet},
    )

Retrieve the total number of linking constraints with function `func_type` and set 
`set_type` in `graph`. Includes constraints in subgraphs.
"""
function num_link_constraints(
    graph::OptiGraph,
    func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
    set_type::Type{<:MOI.AbstractSet},
)
    return sum(JuMP.num_constraints.(all_edges(graph), Ref(func_type), Ref(set_type)))
end

"""
    num_link_constraints(graph::OptiGraph)

Retrieve the number of local linking constraints (all constraint types) in `graph`. 
Does not include constraints in subgraphs.
"""
function num_link_constraints(graph::OptiGraph)
    return sum(JuMP.num_constraints.(all_edges(graph)))
end

"""
    local_link_constraints(
        graph::OptiGraph,
        func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
        set_type::Type{<:MOI.AbstractSet},
    )

Retrieve the local linking constraints with function `func_type` and set 
`set_type` in `graph`. Does not include linking constraints in subgraphs.
"""
function local_link_constraints(
    graph::OptiGraph,
    func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
    set_type::Type{<:MOI.AbstractSet},
)
    return vcat(all_constraints.(local_edges(graph), Ref(func_type), Ref(set_type))...)
end

"""
    local_link_constraints(graph::OptiGraph)

Retrieve the local linking constraints (all constraint types) in `graph`. 
Does not include constraints in subgraphs.
"""
function local_link_constraints(graph::OptiGraph)
    return vcat(all_constraints.(local_edges(graph))...)
end

"""
    all_link_constraints(
        graph::OptiGraph,
        func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
        set_type::Type{<:MOI.AbstractSet},
    )

Retrieve all linking constraints with function `func_type` and set `set_type` in `graph`. 
Does not include constraints in subgraphs.
"""
function all_link_constraints(
    graph::OptiGraph,
    func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
    set_type::Type{<:MOI.AbstractSet},
)
    all_cons = all_constraints.(all_edges(graph), Ref(func_type), Ref(set_type))
    return vcat(all_cons...)
end

"""
    all_link_constraints(graph::OptiGraph)

Retrieve all linking constraints (all constraint types) in `graph`. Includes linking
constraints in subgraphs.
"""
function all_link_constraints(graph::OptiGraph)
    return vcat(all_constraints.(all_edges(graph))...)
end

### Local Constraints

"""
    num_local_constraints(
        graph::OptiGraph,
        func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
        set_type::Type{<:MOI.AbstractSet},
    )

Retrieve the number of local constraints with function `func_type` and set 
`set_type` in `graph`. Does not include constraints in subgraphs.
"""
function num_local_constraints(
    graph::OptiGraph,
    func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
    set_type::Type{<:MOI.AbstractSet},
)
    if num_local_elements(graph) == 0
        return 0
    else
        return sum(
            JuMP.num_constraints.(local_elements(graph), Ref(func_type), Ref(set_type))
        )
    end
end

"""
    num_local_constraints(graph::OptiGraph)

Retrieve the number of local constraints (all constraint types) in `graph`. Does not include
constraints in subgraphs.
"""
function num_local_constraints(graph::OptiGraph)
    if num_local_elements(graph) == 0
        return 0
    else
        return sum(JuMP.num_constraints.(local_elements(graph)))
    end
end

"""
    local_constraints(
        graph::OptiGraph,
        func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
        set_type::Type{<:MOI.AbstractSet},
    )

Retrieve the local constraints with function `func_type` and set `set_type` in `graph`. 
Does not include constraints in subgraphs.
"""
function local_constraints(
    graph::OptiGraph,
    func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
    set_type::Type{<:MOI.AbstractSet},
)
    return vcat(all_constraints.(local_elements(graph), Ref(func_type), Ref(set_type))...)
end

"""
    local_constraints(graph::OptiGraph)

Retrieve the local constraints (all constraint types) in `graph`. Does not include 
constraints in subgraphs.
"""
function local_constraints(graph::OptiGraph)
    return vcat(all_constraints.(local_elements(graph))...)
end

# TODO Methods
# num_linked_variables(graph)
# linked_variables(graph)

#
# MOI Methods
#

function MOI.get(
    graph::OptiGraph, attr::AT
) where {AT<:Union{MOI.AbstractModelAttribute,MOI.AbstractOptimizerAttribute}}
    return MOI.get(graph_backend(graph), attr)
end

function MOI.set(
    graph::OptiGraph, attr::AT, args...
) where {AT<:Union{MOI.AbstractModelAttribute,MOI.AbstractOptimizerAttribute}}
    return MOI.set(graph_backend(graph), attr, args...)
end

#
# JuMP Methods
#

"""
    JuMP.name(graph::OptiGraph)

Return the name of `graph`.
"""
function JuMP.name(graph::OptiGraph)
    return Base.string(graph.label)
end

"""
    JuMP.set_name(graph::OptiGraph, name::Symbol)

Set the name of `graph` to `name`.
"""
function JuMP.set_name(graph::OptiGraph, name::Symbol)
    graph.label = name
    return nothing
end

### Variables

"""
    JuMP.all_variables(graph::OptiGraph)

Return all of the variables in `graph`.
"""
function JuMP.all_variables(graph::OptiGraph)
    return vcat(JuMP.all_variables.(all_nodes(graph))...)
end

"""
    num_local_variables(graph::OptiGraph)

Return the number of local variables in `graph`. Does not include variables in subgraphs.
"""
function num_local_variables(graph::OptiGraph)
    return sum(JuMP.num_variables.(local_nodes(graph)))
end

"""
    JuMP.num_variables(graph::OptiGraph)

Return the total number of variables in `graph`.
"""
function JuMP.num_variables(graph::OptiGraph)
    return sum(JuMP.num_variables.(all_nodes(graph)))
end

"""
    JuMP.index(graph::OptiGraph, nvref::NodeVariableRef)

Return the backend model index of node variable `nvref`
"""
function JuMP.index(graph::OptiGraph, nvref::NodeVariableRef)
    return graph_index(graph, nvref)
end

"""
    JuMP.start_value(graph::OptiGraph, nvref::NodeVariableRef)

Return the start value for variable `nvref` in `graph`. Note that different 
graphs can have different start values for node variables.
"""
function JuMP.start_value(graph::OptiGraph, nvref::NodeVariableRef)
    return MOI.get(graph_backend(graph), MOI.VariablePrimalStart(), nvref)
end

"""
    JuMP.set_start_value(
        graph::OptiGraph, 
        nvref::NodeVariableRef, 
        value::Union{Nothing,Real}
    )

Set the start value of variable `nvref` in `graph`. Note that different 
graphs can have different start values for node variables.
"""
function JuMP.set_start_value(
    graph::OptiGraph, nvref::NodeVariableRef, value::Union{Nothing,Real}
)
    MOI.set(
        graph_backend(graph),
        MOI.VariablePrimalStart(),
        nvref,
        _convert_if_something(Float64, value),
    )
    return nothing
end

"""
    JuMP.value(graph::OptiGraph, nvref::NodeVariableRef; result::Int=1)

Return the primal value of `nvref` in `graph`. Note that this value is specific to 
the optimizer solution to the `graph`. The `nvref` can have different values for 
different optigraphs it is contained in.
"""
function JuMP.value(graph::OptiGraph, nvref::NodeVariableRef; result::Int=1)
    return MOI.get(graph_backend(graph), MOI.VariablePrimal(result), nvref)
end

function JuMP.value(graph::OptiGraph, expr::JuMP.GenericAffExpr; result::Int=1)
    return JuMP.value(expr) do x
        return JuMP.value(graph, x; result=result)
    end
end

function JuMP.value(graph::OptiGraph, expr::JuMP.GenericQuadExpr; result::Int=1)
    return JuMP.value(expr) do x
        return JuMP.value(graph, x; result=result)
    end
end

function JuMP.value(graph::OptiGraph, expr::GenericNonlinearExpr; result::Int=1)
    return value(expr) do x
        return value(graph, x; result=result)
    end
end

"""
    JuMP.dual(graph::OptiGraph, cref::NodeConstraintRef; result::Int=1)

Return the dual value of `cref` in `graph`. Note that this value is specific to 
the optimizer solution to the `graph`. The `cref` can have different values for 
different optigraphs it is contained in.
"""
function JuMP.dual(graph::OptiGraph, cref::NodeConstraintRef; result::Int=1)
    return MOI.get(graph_backend(graph), MOI.ConstraintDual(result), cref)
end

"""
    JuMP.dual(graph::OptiGraph, cref::EdgeConstraintRef; result::Int=1)

Return the dual value of `cref` in `graph`. Note that this value is specific to 
the optimizer solution to the `graph`. The `cref` can have different values for 
different optigraphs it is contained in.
"""
function JuMP.dual(graph::OptiGraph, cref::EdgeConstraintRef; result::Int=1)
    return MOI.get(graph_backend(graph), MOI.ConstraintDual(result), cref)
end

### Constraints

"""
    JuMP.add_constraint(graph::OptiGraph, con::JuMP.AbstractConstraint, name::String="")

Add a new constraint to `graph`. This method is called internall when a user uses the 
JuMP.@constraint macro.
"""
function JuMP.add_constraint(
    graph::OptiGraph, con::JuMP.AbstractConstraint, name::String=""
)
    nodes = collect_nodes(JuMP.jump_function(con))
    @assert length(nodes) > 0
    length(nodes) > 1 || error("Cannot create a linking constraint on a single node")
    edge = add_edge(graph, nodes...)
    con = JuMP.model_convert(edge, con)
    cref = _moi_add_edge_constraint(edge, con)
    return cref
end

"""
    JuMP.list_of_constraint_types(graph::OptiGraph)::Vector{Tuple{Type,Type}}

List all of the constraint types in `graph`.
"""
function JuMP.list_of_constraint_types(graph::OptiGraph)::Vector{Tuple{Type,Type}}
    all_constraint_types = JuMP.list_of_constraint_types.(all_elements(graph))
    return unique(vcat(all_constraint_types...))
end

"""
    JuMP.all_constraints(
        graph::OptiGraph,
        func_type::Type{
            <:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}},
        },
        set_type::Type{<:MOI.AbstractSet}
    )

Return all of the constraints in `graph` with `func_type` and `set_type`.
"""
function JuMP.all_constraints(
    graph::OptiGraph,
    func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
    set_type::Type{<:MOI.AbstractSet},
)
    all_graph_constraints =
        JuMP.all_constraints.(all_elements(graph), Ref(func_type), Ref(set_type))
    return vcat(all_graph_constraints...)
end

"""
    JuMP.all_constraints(graph::OptiGraph)

Return all of the constraints in `graph` (all function and set types).
"""
function JuMP.all_constraints(graph::OptiGraph; include_variable_in_set_constraints=true)
    constraints = ConstraintRef[]
    con_types = JuMP.list_of_constraint_types(graph)
    for con_type in con_types
        F = con_type[1]
        S = con_type[2]
        if F == NodeVariableRef && include_variable_in_set_constraints == false
            continue
        end
        append!(constraints, JuMP.all_constraints(graph, F, S))
    end
    return constraints
end

"""
    JuMP.num_constraints(
        graph::OptiGraph,
        func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
        set_type::Type{<:MOI.AbstractSet},
    )

Return all the number of contraints in `graph` with `func_type` and `set_type`.
"""
function JuMP.num_constraints(
    graph::OptiGraph,
    func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
    set_type::Type{<:MOI.AbstractSet},
)
    return sum(JuMP.num_constraints.(all_elements(graph), Ref(func_type), Ref(set_type)))
end

"""
    JuMP.num_constraints(graph::OptiGraph; count_variable_in_set_constraints=true)

Return the total number of constraints in `graph`. If `count_variable_in_set_constraints`
is set to true, this also includes variable bound constraints. 
"""
function JuMP.num_constraints(graph::OptiGraph; count_variable_in_set_constraints=true)
    num_cons = 0
    con_types = JuMP.list_of_constraint_types(graph)
    for con_type in con_types
        F = con_type[1]
        S = con_type[2]
        if F == NodeVariableRef && count_variable_in_set_constraints == false
            continue
        end
        num_cons += JuMP.num_constraints(graph, F, S)
    end
    return num_cons
end

### Other Methods

"""
    JuMP.backend(graph::OptiGraph)

Return the backend model object for `graph`.
"""
function JuMP.backend(graph::OptiGraph)
    return graph_backend(graph)
end

"""
    JuMP.object_dictionary(graph::OptiGraph)

Return the object dictionary for `graph`.
"""
function JuMP.object_dictionary(graph::OptiGraph)
    return graph.obj_dict
end

"""
    JuMP.relax_integrality(graph::OptiGraph)

Relax all binary and integer constraints in `graph`. Return a function that un-relaxes the
graph by re-adding the binary and/or integer constraints.
"""
function JuMP.relax_integrality(graph::OptiGraph)
    unrelax_node_funcs = JuMP.relax_integrality.(all_nodes(graph))
    function unrelax()
        for func in unrelax_node_funcs
            func()
        end
    end
    return unrelax
end

### Nonlinear Operators

"""
    JuMP.add_nonlinear_operator(
        graph::OptiGraph,
        dim::Int,
        f::Function,
        args::Vararg{Function,N};
        name::Symbol=Symbol(f),
    ) where {N}

Add a nonlinear operator to a `graph`.
"""
function JuMP.add_nonlinear_operator(
    graph::OptiGraph,
    dim::Int,
    f::Function,
    args::Vararg{Function,N};
    name::Symbol=Symbol(f),
) where {N}
    nargs = 1 + N
    if !(1 <= nargs <= 3)
        error(
            "Unable to add operator $name: invalid number of functions " *
            "provided. Got $nargs, but expected 1 (if function only), 2 (if " *
            "function and gradient), or 3 (if function, gradient, and " *
            "hesssian provided)",
        )
    end
    MOI.set(graph, MOI.UserDefinedFunction(name, dim), tuple(f, args...))
    registered_name = graph_operator(
        graph_backend(graph), graph, MOI.UserDefinedFunction(name, dim)
    )
    return JuMP.NonlinearOperator(f, registered_name)
end

### Objective function

"""
    has_node_objective(graph::OptiGraph)

Return whether a graph has an optinode with an objective function.
"""
function has_node_objective(graph::OptiGraph)
    for node in all_nodes(graph)
        if has_objective(node)
            return true
        end
    end
    return false
end

"""
    set_to_node_objectives(graph::OptiGraph)

Set the `graph` objective to the summation of all of its optinode objectives. Assumes the 
objective sense is an MOI.MIN_SENSE and adjusts the signs of node objective functions 
accordingly.
"""
function set_to_node_objectives(graph::OptiGraph)
    obj = 0
    for node in all_nodes(graph)
        if has_objective(node)
            sense = JuMP.objective_sense(node) == MOI.MAX_SENSE ? -1 : 1
            obj += sense * JuMP.objective_function(node)
        end
    end
    if obj != 0
        @objective(graph, Min, obj)
    end
    return nothing
end

"""
    JuMP.objective_function(graph::OptiGraph)

Return the objective function for `graph`.
"""
function JuMP.objective_function(graph::OptiGraph)
    F = MOI.get(graph, MOI.ObjectiveFunctionType())
    return JuMP.objective_function(graph, F)
end

function JuMP.objective_function(
    graph::OptiGraph, ::Type{F}
) where {F<:MOI.AbstractFunction}
    func = MOI.get(JuMP.backend(graph), MOI.ObjectiveFunction{F}())::F
    return JuMP.jump_function(graph, func)
end

function JuMP.objective_function(graph::OptiGraph, ::Type{T}) where {T}
    return JuMP.objective_function(graph, JuMP.moi_function_type(T))
end

"""
    JuMP.objective_sense(graph::OptiGraph)

Return the objective sense for `graph`.
"""
function JuMP.objective_sense(graph::OptiGraph)
    return MOI.get(graph, MOI.ObjectiveSense())
end

"""
    JuMP.objective_sense(graph::OptiGraph)

Return the objective function type for `graph`.
"""
function JuMP.objective_function_type(graph::OptiGraph)
    return JuMP.jump_function_type(graph, MOI.get(graph, MOI.ObjectiveFunctionType()))
end

"""
    JuMP.objective_value(graph::OptiGraph)

Retrieve the current objective value on optigraph `graph`.
"""
function JuMP.objective_value(graph::OptiGraph)
    return MOI.get(graph_backend(graph), MOI.ObjectiveValue())
end

"""
    JuMP.dual_objective_value(graph::OptiGraph; result::Int=1)

Return the dual objective value for `graph`. Specify `result` for cases when 
a solver returns multiple results.
"""
function JuMP.dual_objective_value(graph::OptiGraph; result::Int=1)
    return MOI.get(graph_backend(graph), MOI.DualObjectiveValue(result))
end

"""
    JuMP.relative_gap(graph::OptiGraph)

Return the relative gap in the current solution for `graph`.
"""
function JuMP.relative_gap(graph::OptiGraph)
    return MOI.get(graph, MOI.RelativeGap())
end

"""
    JuMP.objective_bound(graph::OptiGraph)

Return the objective bound for the current solution for `graph`.
"""
function JuMP.objective_bound(graph::OptiGraph)
    return MOI.get(graph, MOI.ObjectiveBound())
end

"""
    JuMP.set_objective(
        graph::OptiGraph, 
        sense::MOI.OptimizationSense, 
        func::JuMP.AbstractJuMPScalar
    )

Set the objective function and objective sense for `graph`. This method is called 
internally when a user uses the `JuMP.@objective` macro.
"""
function JuMP.set_objective(
    graph::OptiGraph, sense::MOI.OptimizationSense, func::JuMP.AbstractJuMPScalar
)
    JuMP.set_objective_sense(graph, sense)
    JuMP.set_objective_function(graph, func)
    return nothing
end

"""
    JuMP.set_objective_sense(graph::OptiGraph, sense::MOI.OptimizationSense)

Set the objective sense of `graph`.
"""
function JuMP.set_objective_sense(graph::OptiGraph, sense::MOI.OptimizationSense)
    MOI.set(graph_backend(graph), MOI.ObjectiveSense(), sense)
    return nothing
end

"""
    JuMP.set_objective_function(graph::OptiGraph, expr::JuMP.AbstractJuMPScalar)

Set the objective function of `graph`.
"""
function JuMP.set_objective_function(graph::OptiGraph, expr::JuMP.AbstractJuMPScalar)
    _moi_set_objective_function(graph, expr)
    return nothing
end

function _moi_set_objective_function(graph::OptiGraph, expr::JuMP.AbstractJuMPScalar)
    # add variables to backend if using subgraphs
    _add_backend_variables(graph_backend(graph), expr)
    # get the moi function made from local node variable indices
    func_type = JuMP.moi_function_type(typeof(expr))
    MOI.set(graph_backend(graph), MOI.ObjectiveFunction{func_type}(), expr)
    return nothing
end

### objective coefficient - linear

"""
    JuMP.set_objective_coefficient(
        graph::OptiGraph, 
        variable::NodeVariableRef, 
        coeff::Real
    )

Set the objective function coefficient for `variable` to coefficient `coeff`.
"""
function JuMP.set_objective_coefficient(
    graph::OptiGraph, variable::NodeVariableRef, coeff::Real
)
    coeff_t = convert(Float64, coeff)
    F = JuMP.objective_function_type(graph)
    _set_objective_coefficient(graph, variable, coeff_t, F)
    graph.is_model_dirty = true
    return nothing
end

function _set_objective_coefficient(
    graph::OptiGraph, variable::NodeVariableRef, coeff::Float64, ::Type{NodeVariableRef}
)
    current_obj = JuMP.objective_function(graph)
    if graph_index(graph, current_obj) == graph_index(graph, variable)
        JuMP.set_objective_function(graph, coeff * variable)
    else
        JuMP.set_objective_function(
            graph, JuMP.add_to_expression!(coeff * variable, current_obj)
        )
    end
    return nothing
end

function _set_objective_coefficient(
    graph::OptiGraph, variable::NodeVariableRef, coeff::Float64, ::Type{F}
) where {F}
    MOI.modify(
        graph_backend(graph),
        MOI.ObjectiveFunction{JuMP.moi_function_type(F)}(),
        variable,
        coeff,
    )
    return nothing
end

### objective coefficient - linear - vector

function JuMP.set_objective_coefficient(
    graph::OptiGraph,
    variables::AbstractVector{<:NodeVariableRef},
    coeffs::AbstractVector{<:Real},
)
    n, m = length(variables), length(coeffs)
    if !(n == m)
        msg = "The number of variables ($n) and coefficients ($m) must match"
        throw(DimensionMismatch(msg))
    end
    F = objective_function_type(graph)
    _set_objective_coefficient(graph, variables, convert.(Float64, coeffs), F)
    graph.is_model_dirty = true
    return nothing
end

function _set_objective_coefficient(
    graph::OptiGraph,
    variables::AbstractVector{<:NodeVariableRef},
    coeffs::AbstractVector{<:Real},
    ::Type{NodeVariableRef},
)
    new_objective = LinearAlgebra.dot(coeffs, variables)
    current_obj = objective_function(model)::NodeVariableRef
    if !(current_obj in variables)
        JuMP.add_to_expression!(new_objective, current_obj)
    end
    JuMP.set_objective_function(model, new_objective)
    return nothing
end

function _set_objective_coefficient(
    graph::OptiGraph,
    variables::AbstractVector{<:NodeVariableRef},
    coeffs::AbstractVector{<:Real},
    ::Type{F},
) where {F}
    MOI.modify(
        graph_backend(graph),
        MOI.ObjectiveFunction{JuMP.moi_function_type(F)}(),
        variables,
        coeffs,
    )
    return nothing
end

### objective coefficient - quadratic

function JuMP.set_objective_coefficient(
    graph::OptiGraph, variable_1::NodeVariableRef, variable_2::NodeVariableRef, coeff::Real
)
    coeff_t = convert(Float64, coeff)::Float64
    F = JuMP.moi_function_type(JuMP.objective_function_type(graph))
    _set_objective_coefficient(graph, variable_1, variable_2, coeff_t, F)
    graph.is_model_dirty = true
    return nothing
end

# if existing objective is not quadratic
function _set_objective_coefficient(
    graph::OptiGraph,
    variable_1::NodeVariableRef,
    variable_2::NodeVariableRef,
    coeff::Float64,
    ::Type{F},
) where {F}
    current_obj = JuMP.objective_function(graph)
    new_obj = JuMP.add_to_expression!(coeff * variable_1 * variable_2, current_obj)
    JuMP.set_objective_function(graph, new_obj)
    return nothing
end

# if existing objective is quadratic
function _set_objective_coefficient(
    graph::OptiGraph,
    variable_1::NodeVariableRef,
    variable_2::NodeVariableRef,
    coeff::Float64,
    ::Type{MOI.ScalarQuadraticFunction{Float64}},
)
    if variable_1 == variable_2
        coeff *= Float64(2)
    end
    MOI.modify(
        graph_backend(graph),
        MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}(),
        variable_1,
        variable_2,
        coeff,
    )
    return nothing
end

### objective coefficient - quadratic - vector

function JuMP.set_objective_coefficient(
    graph::OptiGraph,
    variables_1::AbstractVector{<:NodeVariableRef},
    variables_2::AbstractVector{<:NodeVariableRef},
    coeffs::AbstractVector{<:Real},
)
    n1, n2, m = length(variables_1), length(variables_2), length(coeffs)
    if !(n1 == n2 == m)
        msg = "The number of variables ($n1, $n2) and coefficients ($m) must match"
        throw(DimensionMismatch(msg))
    end
    coeffs_t = convert.(Float64, coeffs)
    F = JuMP.moi_function_type(JuMP.objective_function_type(graph))
    _set_objective_coefficient(graph, variables_1, variables_2, coeffs_t, F)
    graph.is_model_dirty = true
    return nothing
end

# if existing objective is not quadratic
function _set_objective_coefficient(
    graph::OptiGraph,
    variables_1::AbstractVector{<:NodeVariableRef},
    variables_2::AbstractVector{<:NodeVariableRef},
    coeffs::AbstractVector{<:Float64},
    ::Type{F},
) where {F}
    new_obj = JuMP.GenericQuadExpr{Float64,NodeVariableRef}()
    JuMP.add_to_expression!(new_obj, JuMP.objective_function(graph))
    for (c, x, y) in zip(coeffs, variables_1, variables_2)
        JuMP.add_to_expression!(new_obj, c, x, y)
    end
    JuMP.set_objective_function(graph, new_obj)
    return nothing
end

# if existing objective is quadratic
function _set_objective_coefficient(
    graph::OptiGraph,
    variables_1::AbstractVector{<:NodeVariableRef},
    variables_2::AbstractVector{<:NodeVariableRef},
    coeffs::AbstractVector{<:Float64},
    ::Type{MOI.ScalarQuadraticFunction{Float64}},
)
    for (i, x, y) in zip(eachindex(coeffs), variables_1, variables_2)
        if x == y
            coeffs[i] *= Float64(2)
        end
    end
    MOI.modify(
        graph_backend(graph),
        MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}(),
        variables_1,
        variables_2,
        coeffs,
    )
    return nothing
end

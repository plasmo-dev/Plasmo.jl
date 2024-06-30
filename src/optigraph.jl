function OptiGraph(;
    name::Symbol=Symbol(:g,gensym())
)
    graph = OptiGraph(
        name,
        OrderedSet{OptiNode}(),
        OrderedSet{OptiEdge}(),
        OrderedSet{OptiGraph}(),
        OrderedDict{Set{OptiNode},OptiEdge}(),
        nothing,
        OrderedDict{OptiNode,Vector{OptiGraph}}(),
        OrderedDict{OptiEdge,Vector{OptiGraph}}(),
        OrderedDict{OptiNode,OptiGraph}(),
        nothing,
        OrderedDict{Tuple{OptiNode,Symbol},Any}(),
        OrderedDict{Tuple{OptiEdge,Symbol},Any}(),
        Dict{Symbol,Any}(),
        Dict{Symbol,Any}(),
        Set{Any}(),
        false
    )

    # default is MOI backend
    graph.backend = GraphMOIBackend(graph)
    return graph
end

function Base.string(graph::OptiGraph)
    return "OptiGraph" * " " * Base.string(graph.label)
end
Base.print(io::IO, graph::OptiGraph) = Base.print(io, Base.string(graph))
Base.show(io::IO, graph::OptiGraph) = Base.print(io, graph)

function Base.getindex(graph::OptiGraph, idx::Int)
    return graph.optinodes[idx]
end

Base.broadcastable(graph::OptiGraph) = Ref(graph)

# TODO: parameterize on numerical precision like JuMP Models do
JuMP.value_type(::Type{OptiGraph})  = Float64

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

function graph_index(ref::RT) where
    RT <: Union{NodeVariableRef,ConstraintRef}
    return graph_index(graph_backend(JuMP.owner_model(ref)), ref)
end

function graph_index(graph::OptiGraph, ref::RT) where
    RT <: Union{NodeVariableRef,ConstraintRef}
    return graph_index(graph_backend(graph), ref)
end

### Assemble OptiGraph

function _assemble_optigraph(nodes::Vector{OptiNode}, edges::Vector{OptiEdge})
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
    assemble_optigraph(nodes::Vector{OptiNode}, edges::Vector{OptiEdge})

Create a new optigraph from a collection of nodes and edges.
"""
function assemble_optigraph(nodes::Vector{OptiNode}, edges::Vector{OptiEdge})
    is_valid_optigraph(nodes, edges) || error(
        "The provided nodes and edges are not a valid optigraph. 
        All connected edge nodes must be provided in the node vector."
    )
    graph = _assemble_optigraph(nodes, edges)
    return graph
end

function assemble_optigraph(node::OptiNode)
    graph = OptiGraph()
    add_node(graph, node)
    return graph
end

"""
    is_valid_optigraph(nodes::Vector{OptiNode}, edges::Vector{OptiEdge})

Check whether the given nodes and edges can create a valid optigraph.
"""
function is_valid_optigraph(nodes::Vector{OptiNode}, edges::Vector{OptiEdge})
    if length(edges) == 0
        return true
    end
    edge_nodes = union(all_nodes.(edges)...)
    return isempty(setdiff(edge_nodes, nodes)) ? true : false
end

### Manage OptiNodes

function add_node(
    graph::OptiGraph; 
    label=Symbol(graph.label,Symbol(".n"),length(graph.optinodes)+1)
)
    node_index = NodeIndex(gensym()) #NodeIndex(length(graph.optinodes)+1)
    node = OptiNode(Ref(graph), node_index, label)
    push!(graph.optinodes, node)
    _add_node(graph_backend(graph), node)
    return node
end

function add_node(graph::OptiGraph, node::OptiNode)
    node in all_nodes(graph) && error("Cannot add the same node to a graph multiple times")
    push!(graph.optinodes, node)
    _append_node_to_backend!(graph_backend(graph), node)
    return
end

function get_node(graph::OptiGraph, idx::Int)
    return graph.optinodes[idx]
end

"""
    collect_nodes(jump_func::T where T <: JuMP.AbstractJuMPScalar)

Retrieve the optinodes contained in a JuMP expression.
"""
function collect_nodes(
    jump_func::T where T <: JuMP.AbstractJuMPScalar
)
    vars = _extract_variables(jump_func)
    nodes = JuMP.owner_model.(vars)
    return collect(nodes)
end

"""
    local_nodes(graph::OptiGraph)::Vector{OptiNode}

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
    all_nodes(graph::OptiGraph)::Vector{OptiNode}

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

function add_edge(
    graph::OptiGraph,
    nodes::OptiNode...;
    label=Symbol(graph.label, Symbol(".e"), length(graph.optiedges)+1)
)
    if has_edge(graph, Set(nodes))
        edge = get_edge(graph, Set(nodes))
    else
        edge = OptiEdge(Ref(graph), label, OrderedSet(collect(nodes)))
        push!(graph.optiedges, edge)
        graph.optiedge_map[Set(collect(nodes))] = edge
        _add_edge(graph_backend(graph), edge)
    end
    return edge
end

function add_edge(graph::OptiGraph, edge::OptiEdge)
    edge in all_edges(graph) && error("Cannot add the same edge to a graph multiple times")
    push!(graph.optiedges, edge)
    _append_edge_to_backend!(graph_backend(graph), edge)
    return
end

function has_edge(graph::OptiGraph, nodes::Set{OptiNode})
    if haskey(graph.optiedge_map, nodes)
        return true
    else
        return false
    end
end

function get_edge(graph::OptiGraph, nodes::Set{OptiNode})
    return graph.optiedge_map[nodes]
end

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
    all_edges(graph::OptiGraph)::Vector{OptiNode}

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

function local_elements(graph::OptiGraph)
    return [local_nodes(graph); local_edges(graph)]
end

function all_elements(graph::OptiGraph)
    return [all_nodes(graph); all_edges(graph)]
end

### Manage subgraphs

"""
    add_subgraph(graph::OptiGraph; name::Symbol=Symbol(:sg,gensym()))

Create and add a new subgraph to the optigraph `graph`.
"""
function add_subgraph(
    graph::OptiGraph;
    name::Symbol=Symbol(:sg,gensym())
)
    subgraph = OptiGraph(; name=name)
    subgraph.parent_graph=graph
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

function traverse_parents(graph::OptiGraph)
    parents = OptiGraph[]
    if graph.parent_graph != nothing
        push!(parents, graph.parent_graph)
        append!(parents, traverse_parents(graph.parent_graph))
    end
    return parents
end

"""
    get_subgraphs(graph::OptiGraph)::Vector{OptiGraph}

Retrieve the local subgraphs of `graph`.
"""
function local_subgraphs(graph::OptiGraph)
    return graph.subgraphs
end

"""
    num_local_subgraphs(graph::OptiGraph)::Int

Retrieve the number of local subgraphs in `graph`.
"""
function num_local_subgraphs(graph::OptiGraph)
    return length(graph.subgraphs)
end

@deprecate get_subgraphs local_subgraphs

function all_subgraphs(graph::OptiGraph)
    subs = collect(graph.subgraphs)
    for subgraph in graph.subgraphs
        subs = [subs; all_subgraphs(subgraph)]
    end
    return subs
end

function num_subgraphs(graph::OptiGraph)
    n_subs = num_local_subgraphs(graph)
    for subgraph in graph.subgraphs
        n_subs += num_local_subgraphs(subgraph)
    end
    return n_subs
end

### Link Constraints

function num_local_link_constraints(
    graph::OptiGraph,
    func_type::Type{
        <:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}},
    },
    set_type::Type{<:MOI.AbstractSet}
)
    return sum(
        JuMP.num_constraints.(local_edges(graph), Ref(func_type), Ref(set_type))
    )
end

function num_local_link_constraints(graph::OptiGraph)
    return sum(
        JuMP.num_constraints.(local_edges(graph))
    )
end

function num_link_constraints(
    graph::OptiGraph, 
    func_type::Type{
        <:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}},
    },
    set_type::Type{<:MOI.AbstractSet}
)
    return sum(
        JuMP.num_constraints.(all_edges(graph), Ref(func_type), Ref(set_type))
    )
end

function num_link_constraints(graph::OptiGraph)
    return sum(
        JuMP.num_constraints.(all_edges(graph))
    )
end

function local_link_constraints(
    graph::OptiGraph, 
    func_type::Type{
        <:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}},
    },
    set_type::Type{<:MOI.AbstractSet}
)
    return vcat(all_constraints.(local_edges(graph), Ref(func_type), Ref(set_type))...)
end

function local_link_constraints(graph::OptiGraph)
    return vcat(all_constraints.(local_edges(graph))...)
end

function all_link_constraints(
    graph::OptiGraph, 
    func_type::Type{
        <:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}},
    },
    set_type::Type{<:MOI.AbstractSet}
)
    all_cons = all_constraints.(all_edges(graph), Ref(func_type), Ref(set_type))
    return vcat(all_cons...)
end

function all_link_constraints(graph::OptiGraph)
    return vcat(all_constraints.(all_edges(graph))...)
end

### Local Constraints

function num_local_constraints(
    graph::OptiGraph,
    func_type::Type{
        <:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}},
    },
    set_type::Type{<:MOI.AbstractSet}
)
    return sum(
        JuMP.num_constraints.(local_elements(graph), Ref(func_type), Ref(set_type))
    )
end

function num_local_constraints(graph::OptiGraph)
    return sum(
        JuMP.num_constraints.(local_elements(graph))
    )
end

function local_constraints(
    graph::OptiGraph, 
    func_type::Type{
        <:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}},
    },
    set_type::Type{<:MOI.AbstractSet}
)
    return vcat(all_constraints.(local_elements(graph), Ref(func_type), Ref(set_type))...)
end

function local_constraints(graph::OptiGraph)
    return vcat(all_constraints.(local_elements(graph))...)
end

### MOI Methods

function MOI.get(graph::OptiGraph, attr::AT) where
    AT <: Union{MOI.AbstractModelAttribute, MOI.AbstractOptimizerAttribute}
    return MOI.get(graph_backend(graph), attr)
end

function MOI.set(graph::OptiGraph, attr::AT, args...) where
    AT <: Union{MOI.AbstractModelAttribute, MOI.AbstractOptimizerAttribute}
    MOI.set(graph_backend(graph), attr, args...)
end

#
# JuMP Methods
#

### Variables

function JuMP.all_variables(graph::OptiGraph)
    return vcat(JuMP.all_variables.(all_nodes(graph))...)
end

function JuMP.num_variables(graph::OptiGraph)
    return sum(JuMP.num_variables.(all_nodes(graph)))
end

function JuMP.index(graph::OptiGraph, vref::NodeVariableRef)
    return graph_index(graph, vref)    
end

function JuMP.start_value(graph::OptiGraph, nvref::NodeVariableRef)
    return MOI.get(graph_backend(graph), MOI.VariablePrimalStart(), nvref)
end

function JuMP.set_start_value(graph::OptiGraph, nvref::NodeVariableRef, value::Union{Nothing,Real})
    MOI.set(
        graph_backend(graph),
        MOI.VariablePrimalStart(),
        nvref,
        _convert_if_something(Float64, value),
    )
    return
end

function JuMP.value(graph::OptiGraph, nvref::NodeVariableRef; result::Int = 1)
    return MOI.get(graph_backend(graph), MOI.VariablePrimal(result), nvref)
end

function JuMP.value(graph::OptiGraph, expr::JuMP.GenericAffExpr; result::Int = 1)
    return JuMP.value(expr) do x
        return JuMP.value(graph, x; result = result)
    end
end

function JuMP.value(graph::OptiGraph, expr::JuMP.GenericQuadExpr; result::Int = 1)
    return JuMP.value(expr) do x
        return JuMP.value(graph, x; result = result)
    end
end

function JuMP.value(graph::OptiGraph, expr::GenericNonlinearExpr; result::Int = 1)
    return value(expr) do x
        return value(graph, x; result = result)
    end
end

### Expression values

# function JuMP.value(var_value::Function, ex::GenericAffExpr{T,V}) where {T,V}
#     S = Base.promote_op(var_value, V)
#     U = Base.promote_op(*, T, S)
#     ret = convert(U, ex.constant)
#     for (var, coef) in ex.terms
#         ret += coef * var_value(var)
#     end
#     return ret
# end

### Constraints

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

Return all of the constraints in the optigraph `graph` with `func_type` and `set_type`.
"""
function JuMP.all_constraints(
    graph::OptiGraph,
    func_type::Type{
        <:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}},
    },
    set_type::Type{<:MOI.AbstractSet}
)
    all_graph_constraints = JuMP.all_constraints.(
        all_elements(graph), 
        Ref(func_type),
        Ref(set_type)
    )
    return vcat(all_graph_constraints...)
end

function JuMP.all_constraints(graph::OptiGraph)
    constraints = ConstraintRef[]
    con_types = JuMP.list_of_constraint_types(graph)
    for con_type in con_types
        F = con_type[1]
        S = con_type[2]
        append!(constraints, JuMP.all_constraints(graph, F, S))
    end
    return constraints
end

function JuMP.num_constraints(
    graph::OptiGraph, 
    func_type::Type{
        <:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}},
    },
    set_type::Type{<:MOI.AbstractSet}
)
    return sum(
        JuMP.num_constraints.(all_elements(graph), Ref(func_type), Ref(set_type))
    )
end

function JuMP.num_constraints(graph::OptiGraph; count_variable_in_set_constraints=true)
    num_cons = 0
    con_types = JuMP.list_of_constraint_types(graph)
    for con_type in con_types
        F = con_type[1]
        S = con_type[2]
        if F == NodeVariableRef && count_variable_in_set_constraints==false
            continue
        end
        num_cons += JuMP.num_constraints(graph, F, S)
    end
    return num_cons
end

### Other Methods

function JuMP.backend(graph::OptiGraph)
    # TODO: make this just graph backend
    return graph_backend(graph).moi_backend
end

function JuMP.object_dictionary(graph::OptiGraph)
    return graph.obj_dict
end

### Nonlinear Operators

function JuMP.add_nonlinear_operator(
    graph::OptiGraph,
    dim::Int,
    f::Function,
    args::Vararg{Function,N};
    name::Symbol = Symbol(f),
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
    return JuMP.NonlinearOperator(f, name)
end

#
# Objective function
#

function set_to_node_objectives(graph::OptiGraph)
    obj = 0
    for node in all_nodes(graph)
        if has_objective(node)
            sense = JuMP.objective_sense(node) == MOI.MAX_SENSE ? -1 : 1
            obj += sense*JuMP.objective_function(node)
        end
    end
    if obj != 0
        @objective(graph, Min, obj)
    end
    return
end

function JuMP.objective_function(
    graph::OptiGraph,
    ::Type{F},
) where {F<:MOI.AbstractFunction}
    func = MOI.get(JuMP.backend(graph), MOI.ObjectiveFunction{F}())::F
    return JuMP.jump_function(graph, func)
end

function JuMP.objective_function(graph::OptiGraph, ::Type{T}) where {T}
    return JuMP.objective_function(graph, JuMP.moi_function_type(T))
end

function JuMP.objective_function(graph::OptiGraph)
    F = MOI.get(graph, MOI.ObjectiveFunctionType())
    return JuMP.objective_function(graph, F)
end

function JuMP.objective_sense(graph::OptiGraph)
    return MOI.get(graph, MOI.ObjectiveSense())
end

function JuMP.objective_function_type(graph::OptiGraph)
    return JuMP.jump_function_type(
        graph,
        MOI.get(graph, MOI.ObjectiveFunctionType()),
    )
end

"""
    JuMP.objective_value(graph::OptiGraph)

Retrieve the current objective value on optigraph `graph`.
"""
function JuMP.objective_value(graph::OptiGraph)
    return MOI.get(graph_backend(graph), MOI.ObjectiveValue())
end

function JuMP.dual_objective_value(
    graph::OptiGraph;
    result::Int = 1,
)
    return MOI.get(graph_backend(graph), MOI.DualObjectiveValue(result))
end

function JuMP.relative_gap(graph::OptiGraph)
    return MOI.get(graph, MOI.RelativeGap())
end

function JuMP.objective_bound(graph::OptiGraph)
    return MOI.get(graph, MOI.ObjectiveBound())
end

function JuMP.set_objective(
    graph::OptiGraph, sense::MOI.OptimizationSense, func::JuMP.AbstractJuMPScalar
)
    JuMP.set_objective_sense(graph, sense)
    JuMP.set_objective_function(graph, func)
    return
end

function JuMP.set_objective_sense(graph::OptiGraph, sense::MOI.OptimizationSense)
    MOI.set(graph_backend(graph), MOI.ObjectiveSense(), sense)
    return
end

function JuMP.set_objective_function(
    graph::OptiGraph, 
    expr::JuMP.AbstractJuMPScalar
)
    _moi_set_objective_function(graph, expr)
    return
end

function _moi_set_objective_function(
    graph::OptiGraph, 
    expr::JuMP.AbstractJuMPScalar
)
    # get the moi function made from local node variable indices
    moi_func = JuMP.moi_function(expr)
    
    # add variables to backend if using subgraphs
    _add_backend_variables(graph_backend(graph), expr)

    # update the moi function using true graph variable indices
    graph_moi_func = _create_graph_moi_func(graph_backend(graph), moi_func, expr)
    func_type = typeof(graph_moi_func)
    MOI.set(
        graph_backend(graph),
        MOI.ObjectiveFunction{func_type}(),
        graph_moi_func,
    )
    return
end

### objective coefficient - linear

function JuMP.set_objective_coefficient(
    graph::OptiGraph,
    variable::NodeVariableRef,
    coeff::Real,
)
    coeff_t = convert(Float64, coeff)
    F = JuMP.objective_function_type(graph)
    _set_objective_coefficient(graph, variable, coeff_t, F)
    graph.is_model_dirty = true
    return
end

function _set_objective_coefficient(
    graph::OptiGraph,
    variable::NodeVariableRef,
    coeff::Float64,
    ::Type{NodeVariableRef},
)
    current_obj = JuMP.objective_function(graph)
    if graph_index(graph, current_obj) == graph_index(graph, variable)
        JuMP.set_objective_function(graph, coeff * variable)
    else
        JuMP.set_objective_function(
            graph,
            JuMP.add_to_expression!(coeff * variable, current_obj),
        )
    end
    return
end

function _set_objective_coefficient(
    graph::OptiGraph,
    variable::NodeVariableRef,
    coeff::Float64,
    ::Type{F},
) where {F}
    MOI.modify(
        graph_backend(graph),
        MOI.ObjectiveFunction{JuMP.moi_function_type(F)}(),
        variable,
        coeff
    )
    return
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
    return
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
    return
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
        coeffs
    )
    return
end

### objective coefficient - quadratic

function JuMP.set_objective_coefficient(
    graph::OptiGraph,
    variable_1::NodeVariableRef,
    variable_2::NodeVariableRef,
    coeff::Real,
)
    coeff_t = convert(Float64, coeff)::Float64
    F = JuMP.moi_function_type(JuMP.objective_function_type(graph))
    _set_objective_coefficient(graph, variable_1, variable_2, coeff_t, F)
    graph.is_model_dirty = true
    return
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
    return
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
        coeff
    )
    return
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
    return
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
    return
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
        coeffs
    )
    return
end
import CliqueTrees:
    BipartiteGraph,
    cliquetree,
    cliquetree!,
    linegraph,
    neighbors,
    parentindex,
    residual,
    reverse,
    rootindex,
    separator

using JuMP: GenericAffExpr, add_to_expression!

function get_edge_to_node(graph::OptiGraph)
    nodes = all_nodes(graph)
    edges = all_edges(graph)
    node_to_idx = Dict(node => i for (i, node) in enumerate(nodes))

    I = Int[]
    J = Int[]

    for (e, edge) in enumerate(edges)
        for node in all_nodes(edge)
            push!(I, node_to_idx[node])
            push!(J, e)
        end
    end

    matrix = sparse(I, J, ones(Int, length(I)), length(nodes), length(edges))
    return BipartiteGraph(matrix)
end

function opti_clique_tree(graph::OptiGraph; kw...)
    nodes = all_nodes(graph)
    edges = all_edges(graph)

    # Construct hypergraph
    edge_to_node = get_edge_to_node(graph)
    node_to_edge = reverse(edge_to_node)

    # Find integral nodes
    int_nodes = [
        i for i in eachindex(nodes)
        if any(v -> JuMP.is_binary(v) || JuMP.is_integer(v), JuMP.all_variables(nodes[i]))
    ]

    # Construct line graph, forcing integer nodes to form a clique
    node_to_node = sparse(linegraph(node_to_edge, edge_to_node))
    node_to_node[int_nodes, int_nodes] .= 1

    # Construct clique tree
    perm, tree = cliquetree(node_to_node; kw...)

    # Pivot clique tree, moving integer nodes to root
    if !isempty(int_nodes)
        invp = invperm(perm)
        permute!(perm, cliquetree!(tree, invp[int_nodes]))
    end

    # Assign each edge to its highest containing bag
    edge_to_bag = zeros(Int, length(edges))

    for j in eachindex(tree)
        for v in residual(tree, j)
            for e in neighbors(node_to_edge, perm[v])
                if edge_to_bag[e] == 0
                    edge_to_bag[e] = j
                end
            end
        end
    end

    return perm, tree, edge_to_bag
end

function apply_clique_tree!(
    graph::OptiGraph,
    perm::AbstractVector{<:Integer},
    tree,
    edge_to_bag::AbstractVector{<:Integer}
)
    optinodes = all_nodes(graph)[perm]
    optiedges = all_edges(graph)

    empty!(graph.optinodes)
    empty!(graph.optiedges)

    V = NodeVariableRef
    bag_to_var_map = [Dict{V, V}() for _ in eachindex(tree)]
    bag_to_graph = Vector{OptiGraph}(undef, length(tree))

    # For each bag in the clique tree, construct a
    # subgraph on the residual
    for j in eachindex(tree)
        subgraph = bag_to_graph[j] = OptiGraph()

        for v in residual(tree, j)
            add_node(subgraph, optinodes[v])
        end

        set_to_node_objectives(subgraph)
        add_subgraph(graph, subgraph)
    end

    # Link each bag with its parent using equality constraints
    for j in Base.Iterators.reverse(eachindex(tree))
        for v in residual(tree, j)
            node = optinodes[v]

            for var in JuMP.all_variables(node)
                bag_to_var_map[j][var] = var
            end
        end

        k = parentindex(tree, j)

        if !isnothing(k)
            @optinode(bag_to_graph[j], _sep_copy_node)

            for v in separator(tree, j)
                node = optinodes[v]

                for orig_var in JuMP.all_variables(node)
                    copy_var = @variable(bag_to_graph[j][:_sep_copy_node])
                    bag_to_var_map[j][orig_var] = copy_var
                    @linkconstraint(graph, copy_var == bag_to_var_map[k][orig_var])
                end
            end
        end
    end

    # Add internal constraints to each bag
    for (e, j) in enumerate(edge_to_bag)
        for con in JuMP.all_constraints(optiedges[e])
            con_obj = JuMP.constraint_object(con)
            _add_substituted_constraint!(con_obj, bag_to_graph[j], bag_to_var_map[j])
        end
    end

    root = rootindex(tree)
    return bag_to_graph[root]
end

"""
    apply_clique_tree!(graph::OptiGraph; kw...)

Transform an opti-graph into a tree of subgraphs.
"""
function apply_clique_tree!(graph::OptiGraph; kw...)
    perm, tree, edge_to_bag = opti_clique_tree(graph; kw...)
    return apply_clique_tree!(graph, perm, tree, edge_to_bag)
end

function _add_substituted_constraint!(
    con_obj::JuMP.ScalarConstraint{GenericAffExpr{Float64, V}, S},
    subgraph::OptiGraph,
    var_map::Dict{V, V}
) where {V <: JuMP.AbstractVariableRef, S}
    new_expr = GenericAffExpr{Float64, V}()

    first_node = nothing
    is_link = false

    for (var, coef) in con_obj.func.terms
        sub_var = var_map[var]
        add_to_expression!(new_expr, coef, sub_var)
        node = JuMP.owner_model(sub_var)

        if isnothing(first_node)
            first_node = node
        elseif node != first_node
            is_link = true
        end
    end

    new_expr.constant = con_obj.func.constant

    if is_link
        _add_link_constraint!(subgraph, new_expr, con_obj.set)
    else
        _add_node_constraint!(first_node, new_expr, con_obj.set)
    end
end

function _add_node_constraint!(node::OptiNode, expr::GenericAffExpr, set::MOI.LessThan)
    @constraint(node, expr <= set.upper)
end

function _add_node_constraint!(node::OptiNode, expr::GenericAffExpr, set::MOI.GreaterThan)
    @constraint(node, expr >= set.lower)
end

function _add_node_constraint!(node::OptiNode, expr::GenericAffExpr, set::MOI.EqualTo)
    @constraint(node, expr == set.value)
end

function _add_link_constraint!(sg::OptiGraph, expr::GenericAffExpr, set::MOI.LessThan)
    @linkconstraint(sg, expr <= set.upper)
end

function _add_link_constraint!(sg::OptiGraph, expr::GenericAffExpr, set::MOI.GreaterThan)
    @linkconstraint(sg, expr >= set.lower)
end

function _add_link_constraint!(sg::OptiGraph, expr::GenericAffExpr, set::MOI.EqualTo)
    @linkconstraint(sg, expr == set.value)
end

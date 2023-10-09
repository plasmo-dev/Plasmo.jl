module TestOptiGraph

using Plasmo, JuMP
using Ipopt, GLPK
using Test

function _create_optigraph()
    graph = OptiGraph()

    @optinode(graph, n1)
    @optinode(graph, n2)
    @optinode(graph, n3)
    @optinode(graph, n4)

    @variable(n1, 0 <= x <= 2, start = 1)
    @variable(n1, 0 <= y <= 3)
    @NLconstraint(n1, x^3 + y <= 4)

    vals = collect(1:5)
    grid = 1:3
    @variable(n2, x >= 1)
    @variable(n2, 0 <= y <= 5)
    @variable(n2, z[1:5] >= 0)
    @variable(n2, a[vals, grid] >= 0)
    @NLconstraint(n2, exp(x) + y <= 7)

    @variable(n3, x[1:5])
    @variable(n4, x >= 1)

    @linkconstraint(graph, n4[:x] == n1[:x])
    @linkconstraint(graph, [t = 1:5], n4[:x] == n2[:z][t])
    @linkconstraint(graph, [i = 1:5], n3[:x][i] == n1[:x])
    @linkconstraint(graph, [j = 1:5, i = 1:3], n2[:a][j, i] == n4[:x])
    @linkconstraint(graph, [i = 1:3], n1[:x] + n2[:z][i] + n3[:x][i] + n4[:x] >= 0)

    @objective(graph, Min, n1[:x] + n2[:x])
    return graph
end

function test_optigraph1()
    graph = OptiGraph()
    @optinode(graph, n1)
    @optinode(graph, nodes1[1:5])
    @optinode(graph, nodes2[1:3, 1:3])

    for node in all_nodes(graph)
        @variable(node, x >= 0)
        @variable(node, y >= 2)
        @constraint(node, x + y == 3)
        @objective(node, Min, y)
    end

    @linkconstraint(graph, n1[:x] == nodes1[1][:x])
    @linkconstraint(graph, sum(nodes1[i][:x] for i in 1:5) == 5)
    @linkconstraint(graph, nodes2[2][:y] == nodes2[3][:y], attach = nodes2[2])

    @test num_nodes(graph) == 15
    @test num_edges(graph) == 3
    @test num_linkconstraints(graph) == 3
    @test num_variables(graph) == 30
    @test has_node_objective(graph) == true

    JuMP.set_optimizer(graph, GLPK.Optimizer)
    optimize!(graph)

    @test objective_value(graph) == 30.0
    @test value(objective_function(graph)) == 30.0

    obj = objective_function(graph)
    @test length(optinodes(obj)) == 15

    JuMP.set_objective_function(graph, n1[:x])
    obj = objective_function(graph)
    @test length(optinodes(obj)) == 1

    JuMP.set_objective_function(graph, n1[:x]^2)
    @test length(optinodes(obj)) == 1

    JuMP.set_objective_coefficient(graph, n1[:x], 2)
    @test objective_function(graph).aff.terms[n1[:x]] == 2.0
end

function test_optigraph2()
    graph = _create_optigraph()
    @test Plasmo.has_nlp_data(graph) == true
    @test Plasmo.has_objective(graph) == true
    @test Plasmo.has_nl_objective(graph) == false
    @test Plasmo.has_node_objective(graph) == false

    #test quadratic objective
    @objective(graph, Min, graph[1][:x]^2 + graph[2][:x]^2 + graph[4][:x])
    set_optimizer(graph, optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0))
    optimize!(graph)
    @test isapprox(objective_value(graph), 3.0; atol=1e-6)
end

function test_set_model_with_graph()
    graph = OptiGraph()

    n1 = @optinode(graph)
    n2 = @optinode(graph)

    m1 = JuMP.Model()
    JuMP.@variable(m1, 0 <= x <= 2)
    JuMP.@variable(m1, 0 <= y <= 3)
    JuMP.@constraint(m1, x + y <= 4)
    JuMP.@objective(m1, Min, x)

    m2 = JuMP.Model()
    JuMP.@variable(m2, x)
    JuMP.@NLconstraint(m2, ref, exp(x) >= 2)

    #Set models on nodes and edges
    set_model(n1, m1)     #set m1 to node 1.  Updates reference on m1
    set_model(n2, m2)

    @test optinodes(graph) == [n1, n2]
    @test all_nodes(graph) == [n1, n2]
    @test optinode_by_index(graph, 1) == n1
    @test optinode_by_index(graph, 2) == n2
    @test Base.getindex(graph, n1) == 1

    @linkconstraint(graph, n1[:x] == n2[:x])
    @test num_variables(graph) == 3

    set_optimizer(graph, optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0))
    optimize!(graph)
    @test termination_status(graph) == MOI.LOCALLY_SOLVED
    @test isapprox(value(n1[:x]), log(2); atol=1e-8)
    @test isapprox(value(graph, n1[:x]), log(2); atol=1e-8)
    @test isapprox(objective_value(graph), log(2); atol=1e-8)

    cref = linkconstraints(graph)[1]
    @test isapprox(dual(cref), 1.0; atol=1e-8)
    @test isapprox(dual(graph, cref), 1.0; atol=1e-8)

    m3 = JuMP.Model()
    JuMP.@variable(m3, x)
    JuMP.@NLconstraint(m3, ref, exp(x) >= 2)
    add_node!(graph, m3)
    @test num_nodes(graph) == 3
    @test num_variables(graph) == 4

    # NOTE: this rebuilds the backend since a new node is added.
    # TODO: fix bug. this is not working
    optimize!(graph)
    @test termination_status(graph) == MOI.LOCALLY_SOLVED
end

function test_subgraph()
    graph = OptiGraph()

    @optinode(graph, n0)
    @variable(n0, x)

    sg1 = OptiGraph()
    sg2 = OptiGraph()
    add_subgraph!(graph, sg1)
    add_subgraph!(graph, sg2)

    @optinode(sg1, ng1[1:5])
    @optinode(sg2, ng2[1:5])

    for node in optinodes(sg1)
        @variable(node, 0 <= x <= 2)
        @objective(node, Max, x)
    end

    for node in optinodes(sg2)
        @variable(node, x >= 2)
        @objective(node, Min, x)
    end

    @linkconstraint(sg1, sum(ng1[i][:x] for i in 1:5) <= 4)
    @linkconstraint(sg2, sum(ng2[i][:x] for i in 1:5) >= 4)

    @linkconstraint(graph, n0[:x] == ng1[1][:x])
    @linkconstraint(graph, n0[:x] == ng2[1][:x])

    @test num_nodes(graph) == 1
    @test num_all_nodes(graph) == 11
    @test num_edges(graph) == 2
    @test num_all_edges(graph) == 4
    @test num_subgraphs(graph) == 2
    @test length(subgraphs(graph)) == 2
    @test num_all_subgraphs(graph) == 2
    @test num_all_linkconstraints(graph) == 4
    @test num_constraints(graph) == 0
    @test num_all_constraints(graph) == 0

    edgs = optiedges(graph)
    @test Plasmo._is_valid_optigraph(ng1, edgs) == false

    @test optiedge_by_index(graph, 1) == edgs[1]
    @test Base.getindex(graph, edgs[1]) == 1

    con_types = JuMP.list_of_constraint_types(graph)
    @test length(con_types) == 2
    var_greater = JuMP.all_constraints(graph, JuMP.VariableRef, MOI.GreaterThan{Float64})
    @test length(var_greater) == 10
end

function test_optigraph_reference()
    graph = _create_optigraph()
    optigraph_ref = optigraph_reference(graph)

    @test num_all_nodes(optigraph_ref) == num_all_nodes(graph)
    @test num_all_variables(optigraph_ref) == num_all_variables(graph)
    @test num_constraints(optigraph_ref) == num_constraints(graph)
    @test num_all_linkconstraints(optigraph_ref) == num_all_linkconstraints(graph)
end

function test_multiple_solves()
    graph = _create_optigraph()
    n1 = optinode(graph, 1)
    set_optimizer(graph, optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0))
    optimize!(graph)
    @test isapprox(value(n1[:x]), 1, atol=1e-6)

    set_lower_bound(n1[:x], 1.5)
    optimize!(graph)
    @test isapprox(value(n1[:x]), 1.5, atol=1e-6)

    set_start_value(n1[:x], 10)
    optimize!(graph)
    @test isapprox(value(n1[:x]), 1.5, atol=1e-6)
    @test start_value(n1[:x]) == 10

    # TODO: support variable attributes on optigraph
    set_start_value(graph, n1[:x], 20)
    optimize!(graph)
    @test isapprox(value(n1[:x]), 1.5, atol=1e-6)
    @test start_value(graph, n1[:x]) == 20
    @test graph.moi_backend.optimizer.model.variable_primal_start[1] == 20
end

function test_fix_variable()
    graph = _create_optigraph()
    n1 = optinode(graph, 1)
    fix(n1[:x], 1; force=true)
    set_optimizer(graph, optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0))
    optimize!(graph)
    @test value(n1[:x]) == 1

    fix(n1[:x], 2)
    optimize!(graph)
    @test value(n1[:x]) == 2

    fix(n1[:x], 0)
    optimize!(graph)
    @test value(n1[:x]) == 0
end

function test_set_optimizer_attributes()
    graph = _create_optigraph()
    set_optimizer(graph, optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0))
    JuMP.set_optimizer_attribute(graph, "max_cpu_time", 1e2)
    @test JuMP.get_optimizer_attribute(graph, "max_cpu_time") == 100.0
end

function test_nlp_exceptions()
    graph = _create_optigraph()
    @test_throws Exception JuMP._init_NLP(graph)
    @test_throws Exception @NLconstraint(graph, graph[1][:x]^3 >= 0)
end

function test_multiple_graphs()
    graph = OptiGraph()
    set_optimizer(graph, Ipopt.Optimizer)
    @optinode(graph, nodes[1:4])
    for (i, node) in enumerate(nodes)
        @variable(node, x >= i)
        @objective(node, Min, 2 * x)
    end
    for i in 1:3
        @linkconstraint(graph, nodes[i + 1][:x] + nodes[i][:x] >= i * 4)
    end

    node_membership = [1, 1, 2, 2]
    hypergraph, hyper_map = hyper_graph(graph)
    partition = Partition(hypergraph, node_membership, hyper_map)
    apply_partition!(graph, partition)
    subs = subgraphs(graph)
    expanded_subgraphs = Plasmo.expand.(graph, subs, 1)

    set_optimizer(
        expanded_subgraphs[1],
        optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0),
    )
    set_optimizer(
        expanded_subgraphs[2],
        optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0),
    )

    middle_link = graph.optiedges[1].linkrefs[1]
    optimize!(expanded_subgraphs[1])
    dual1 = dual(middle_link)
    optimize!(expanded_subgraphs[2])
    dual2 = dual(middle_link)

    @test dual(expanded_subgraphs[1], middle_link) == dual1
    @test dual(expanded_subgraphs[2], middle_link) == dual2
end

function run_tests()
    for name in names(@__MODULE__; all=true)
        if !startswith("$(name)", "test_")
            continue
        end
        @testset "$(name)" begin
            getfield(@__MODULE__, name)()
        end
    end
end

end

TestOptiGraph.run_tests()

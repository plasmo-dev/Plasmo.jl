module TestOptiGraph

using Plasmo
using Ipopt
using Test

function test_simple_graph()
    graph = OptiGraph()
    @optinode(graph, nodes[1:2])

    @variable(nodes[1], x >= 1)
    @variable(nodes[2], x >= 2)
    @linkconstraint(graph, nodes[1][:x] + nodes[2][:x] == 4)
    @objective(graph, Max, nodes[1][:x] + 2*nodes[2][:x])

    set_optimizer(graph, HiGHS.Optimizer)
    optimize!(graph)

    @test objective_value(graph) == 7.0
    @test value(nodes[1][:x]) == 1.0
    @test value(nodes[2][:x]) == 3.0

    
    @test JuMP.termination_status(graph) == MOI.OPTIMAL

    # primal status


end

function _create_test_nl_optigraph()
    graph = OptiGraph()

    n1 = add_node(graph)
    n2 = add_node(graph)
    n3 = add_node(graph)
    n4 = add_node(graph)

    @variable(n1, 0 <= x <= 2, start = 1)
    @variable(n1, 0 <= y <= 3)
    @constraint(n1, x^2 + y^2 <= 4)

    vals = collect(1:5)
    grid = 1:3
    @variable(n2, x >= 1)
    @variable(n2, 0 <= y <= 5)
    @variable(n2, z[1:5] >= 0)
    @variable(n2, a[vals, grid] >= 0)
    @constraint(n2, exp(x) + y <= 7)

    @variable(n3, x[1:5])
    @variable(n4, x >= 1)

    @linkconstraint(graph, n4[:x] == n1[:x])
    @linkconstraint(graph, [t = 1:5], n4[:x] == n2[:z][t])
    @linkconstraint(graph, [i = 1:5], n3[:x][i] == n1[:x])
    @linkconstraint(graph, [j = 1:5, i = 1:3], n2[:a][j, i] == n4[:x])
    @linkconstraint(graph, [i = 1:3], n1[:x] + n2[:z][i] + n3[:x][i] + n4[:x] >= 0)

    @objective(graph, Min, n1[:x] + n2[:x] + n3[:x][1] + n4[:x])
    return graph
end

function test_optigraph()
    graph = _create_test_nl_optigraph()

    @test num_nodes(graph) == 4
    @test num_edges(graph) == 4
    @test num_link_constraints(graph) == 29
    @test num_variables(graph) == 30
    @test length(collect_nodes(objective_function(graph))) == 4
    @test JuMP.objective_function_type(graph) == JuMP.GenericAffExpr{Float64, Plasmo.NodeVariableRef}

    n1,n2,n3,n4 = all_nodes(graph)

    # set objective coefficients
    JuMP.set_objective_coefficient(graph, n1[:x], 2.0)
    @test JuMP.objective_function(graph) == 2*n1[:x] + n2[:x] + n3[:x][1] + n4[:x]
    JuMP.set_objective_coefficient(graph, [n1[:x],n2[:x]], [2.0,2.0])
    @test JuMP.objective_function(graph) == 2*n1[:x] + 2*n2[:x] + n3[:x][1] + n4[:x]

    # set single variable objective
    JuMP.set_objective_function(graph, n1[:x])
    @test JuMP.objective_function_type(graph) == Plasmo.NodeVariableRef
    @test length(collect_nodes(objective_function(graph))) == 1
    @test JuMP.objective_function(graph) == n1[:x]
    JuMP.set_objective_coefficient(graph, n1[:x], 2.0)
    @test JuMP.objective_function(graph) == 2*n1[:x]
    JuMP.set_objective_coefficient(graph, [n1[:x],n2[:x]], [2.0,2.0])
    @test JuMP.objective_function(graph) == 2*n1[:x] + 2*n2[:x]

    # quadratic objective
    JuMP.set_objective_function(graph, n1[:x]^2 + n2[:x]^2)
    @test objective_function(graph) == n1[:x]^2 + n2[:x]^2

    # nonlinear objective
    JuMP.set_objective_function(graph, n1[:x]^3 + n2[:x]^3)
    # NOTE: comparison doesn't seem to work with nonlinear expressions
    # @test objective_function(graph) == n1[:x]^3.0 + n2[:x]^3.0

    JuMP.set_optimizer(graph, Ipopt.Optimizer)
    JuMP.optimize!(graph)
    @test graph.is_model_dirty == false
    @test JuMP.termination_status(graph) == MOI.LOCALLY_SOLVED
    @test isapprox(objective_value(graph), 4.0)
    @test isapprox(value(objective_function(graph)), 4.0)

end


# function test_set_model()
#     graph = OptiGraph()

#     n1 = @optinode(graph)
#     n2 = @optinode(graph)

#     m1 = JuMP.Model()
#     JuMP.@variable(m1, 0 <= x <= 2)
#     JuMP.@variable(m1, 0 <= y <= 3)
#     JuMP.@constraint(m1, x + y <= 4)
#     JuMP.@objective(m1, Min, x)

#     m2 = JuMP.Model()
#     JuMP.@variable(m2, x)
#     JuMP.@constraint(m2, ref, exp(x) >= 2)

#     #Set models on nodes and edges
#     set_model(n1, m1)     #set m1 to node 1.  Updates reference on m1
#     set_model(n2, m2)

#     @test optinodes(graph) == [n1, n2]
#     @test all_nodes(graph) == [n1, n2]
#     @test optinode_by_index(graph, 1) == n1
#     @test optinode_by_index(graph, 2) == n2
#     @test Base.getindex(graph, n1) == 1

#     @linkconstraint(graph, n1[:x] == n2[:x])
#     @test num_variables(graph) == 3

#     set_optimizer(graph, optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0))
#     optimize!(graph)
#     @test termination_status(graph) == MOI.LOCALLY_SOLVED
#     @test isapprox(value(n1[:x]), log(2); atol=1e-8)
#     @test isapprox(value(graph, n1[:x]), log(2); atol=1e-8)
#     @test isapprox(objective_value(graph), log(2); atol=1e-8)

#     cref = linkconstraints(graph)[1]
#     @test isapprox(dual(cref), 1.0; atol=1e-8)
#     @test isapprox(dual(graph, cref), 1.0; atol=1e-8)

#     m3 = JuMP.Model()
#     JuMP.@variable(m3, x)
#     JuMP.@NLconstraint(m3, ref, exp(x) >= 2)
#     add_node!(graph, m3)
#     @test num_nodes(graph) == 3
#     @test num_variables(graph) == 4

#     # NOTE: this rebuilds the backend since a new node is added.
#     # TODO: fix bug. this is not working
#     optimize!(graph)
#     @test termination_status(graph) == MOI.LOCALLY_SOLVED
# end

function test_subgraphs()
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

    @test get_edge(graph, 1) == edgs[1]
    @test Base.getindex(graph, edgs[1]) == 1

    con_types = JuMP.list_of_constraint_types(graph)
    @test length(con_types) == 2
    var_greater = JuMP.all_constraints(graph, JuMP.VariableRef, MOI.GreaterThan{Float64})
    @test length(var_greater) == 10
end

function test_assemble_optigraph()
    graph = _create_optigraph()
    optigraph_ref = assemble_optigraph(all_nodes(graph), all_edges(graph))

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

function test_variables()
    graph = _create_optigraph()
    n1 = get_node(graph, 1)
    JuMP.fix(n1[:x], 1; force=true)
    set_optimizer(graph, optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0))
    optimize!(graph)
    @test value(n1[:x]) == 1

    JuMP.fix(n1[:x], 2)
    optimize!(graph)
    @test value(n1[:x]) == 2

    JuMP.fix(n1[:x], 0)
    optimize!(graph)
    @test value(n1[:x]) == 0
end

function test_optimizer_attributes()
    graph = _create_optigraph()
    set_optimizer(graph, optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0))
    JuMP.set_optimizer_attribute(graph, "max_cpu_time", 1e2)
    @test JuMP.get_optimizer_attribute(graph, "max_cpu_time") == 100.0
end

function test_nlp_exceptions()
    @test_throws Exception @NLconstraint(graph, graph[1][:x]^3 >= 0)
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

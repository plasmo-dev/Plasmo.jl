#  Copyright 2021, Jordan Jalving, Yankai Cao, Victor Zavala, and contributors
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at https://mozilla.org/MPL/2.0/.

using Plasmo
using Ipopt
using HiGHS
using Test
using Distributed
using DistributedArrays

if nprocs() < 2
    addprocs(1)
end
@everywhere begin
    using Plasmo, Ipopt, HiGHS, Test, Distributed, DistributedArrays
end

module TestRemoteOptiGraph

using Plasmo
using Ipopt
using HiGHS
using Test
using Distributed
using DistributedArrays

function test_simple_remote_graph()

    graph = RemoteOptiGraph(worker = 2)
    @optinode(graph, nodes[1:2])

    @variable(nodes[1], x >= 1)
    @variable(nodes[2], x >= 2)
    @linkconstraint(graph, nodes[1][:x] + nodes[2][:x] == 4)
    @objective(graph, Max, nodes[1][:x] + 2 * nodes[2][:x])

    JuMP.set_silent(graph)
    @test MOIU.state(graph) == MOIU.NO_OPTIMIZER
    set_optimizer(graph, HiGHS.Optimizer)
    set_optimizer_attribute(graph, "output_flag", false)
    @test MOIU.state(graph) == MOIU.EMPTY_OPTIMIZER
    optimize!(graph)
    @test MOIU.state(graph) == MOIU.ATTACHED_OPTIMIZER

    @test objective_value(graph) == 7.0
    @test value(nodes[1][:x]) == 1.0
    @test value(nodes[2][:x]) == 3.0
    @test value(nodes[1][:x] + nodes[2][:x]) == value(graph, nodes[1][:x] + nodes[2][:x])
    @test value(nodes[1][:x]^2 + nodes[2][:x]^2) ==
        value(graph, nodes[1][:x]^2 + nodes[2][:x]^2)
    @test value(nodes[1][:x]^3 + nodes[2][:x]^3) ==
        value(graph, nodes[1][:x]^3 + nodes[2][:x]^3)

    @test JuMP.termination_status(graph) == MOI.OPTIMAL
    @test JuMP.primal_status(graph) == MOI.FEASIBLE_POINT
    @test JuMP.dual_status(graph) == MOI.FEASIBLE_POINT

    constraints = all_constraints(graph, include_variable_in_set_constraints=true)

    @test JuMP.dual(constraints[1]) == 1.0
    @test JuMP.dual(constraints[2]) == 0.0
    @test JuMP.dual(constraints[3]) == -2.0

    MOIU.reset_optimizer(graph)
    @test MOIU.state(graph) == MOIU.EMPTY_OPTIMIZER
    MOIU.attach_optimizer(graph)
    @test MOIU.state(graph) == MOIU.ATTACHED_OPTIMIZER
    MOIU.drop_optimizer(graph)
    @test MOIU.state(graph) == MOIU.NO_OPTIMIZER

    # test separable
    @test is_separable(objective_function(graph))
    sep_terms = extract_separable_terms(objective_function(graph), graph)
    @test sep_terms[nodes[1]][1] == 1 * nodes[1][:x]
    @test sep_terms[nodes[2]][1] == 2 * nodes[2][:x]

    @objective(graph, Min, nodes[1][:x]^2 + nodes[2][:x]^2)
    @test is_separable(objective_function(graph))
    sep_terms = extract_separable_terms(objective_function(graph), graph)
    @test sep_terms[nodes[1]][1] == 1 * nodes[1][:x]^2
    @test sep_terms[nodes[2]][1] == 1 * nodes[2][:x]^2

    @objective(graph, Min, nodes[1][:x]^3 + nodes[2][:x]^3)
    @test is_separable(objective_function(graph))
    sep_terms = extract_separable_terms(objective_function(graph), graph)
    @test sep_terms[nodes[1]][1] isa JuMP.GenericNonlinearExpr{RemoteVariableRef}
    @test sep_terms[nodes[2]][1] isa JuMP.GenericNonlinearExpr{RemoteVariableRef}

    @objective(graph, Min, nodes[1][:x]^2 + nodes[2][:x]^2 + nodes[1][:x] * nodes[2][:x])
    @test is_separable(objective_function(graph)) == false

    @objective(graph, Min, nodes[1][:x]^3 * nodes[2][:x]^2)
    @test is_separable(objective_function(graph)) == false
end

function _create_test_nonlinear_optigraph()
    
    graph = RemoteOptiGraph(worker = 2)

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

function test_optigraph_build()
    graph = _create_test_nonlinear_optigraph()

    # basic queries
    @test num_nodes(graph) == 4
    @test num_remote_edges(graph) == 4
    @test num_subgraphs(graph) == 0

    n1, n2, n3, n4 = all_nodes(graph)
    e1, e2, e3, e4 = all_remote_edges(graph)

    @test has_edge(graph, Set([n2, n4])) == true
    @test get_edge(graph, Set([n2, n4])) == e2
    @test all_nodes(e2) == [n4, n2]
    @test all_elements(graph) == [n1, n2, n3, n4, e1, e2, e3, e4]

    # variables
    n1_vars = all_variables(n1)
    @test num_variables(n1) == 2
    @test num_variables(graph) == 30
    @test index(graph, n1[:x]) == MOI.VariableIndex(1)
    @test index(graph, n2[:x]) == MOI.VariableIndex(3)

    # constraints
    @test num_constraints(n1) == 5
    @test num_constraints(e1) == 1
    @test num_constraints(graph) == 31
    @test num_constraints(graph; count_variable_in_set_constraints=true) == 59

    con_types = list_of_constraint_types(graph)
    F, S = con_types[3]
    @test length(con_types) == 6
    @test num_constraints(graph, F, S) == 1
    @test num_remote_link_constraints(graph) == 29
    @test num_remote_link_constraints(graph, F, S) == 0

    @test length(collect_nodes(objective_function(graph))) == 4
    @test JuMP.objective_function_type(graph) ==
        JuMP.GenericAffExpr{Float64,Plasmo.NodeVariableRef}
end

function test_objective_functions()
    graph = _create_test_nonlinear_optigraph()
    n1, n2, n3, n4 = all_nodes(graph)

    # linear objective
    JuMP.set_objective_coefficient(graph, n1[:x], 2.0)
    @test JuMP.objective_function(graph) == 2 * n1[:x] + n2[:x] + n3[:x][1] + n4[:x]

    JuMP.set_objective_coefficient(graph, [n1[:x], n2[:x]], [2.0, 2.0])
    @test JuMP.objective_function(graph) == 2 * n1[:x] + 2 * n2[:x] + n3[:x][1] + n4[:x]

    JuMP.set_objective_function(graph, n1[:x])
    @test JuMP.objective_function_type(graph) == Plasmo.NodeVariableRef
    @test length(collect_nodes(objective_function(graph))) == 1
    @test JuMP.objective_function(graph) == n1[:x]

    JuMP.set_objective_coefficient(graph, n1[:x], 2.0)
    @test JuMP.objective_function(graph) == 2 * n1[:x]

    JuMP.set_objective_coefficient(graph, [n1[:x], n2[:x]], [2.0, 2.0])
    @test JuMP.objective_function(graph) == 2 * n1[:x] + 2 * n2[:x]

    # quadratic objective
    JuMP.set_objective_function(graph, n1[:x]^2 + n2[:x]^2)
    @test objective_function(graph) == n1[:x]^2 + n2[:x]^2

    JuMP.set_objective_coefficient(graph, n1[:x], n1[:x], 3.0)
    @test objective_function(graph) == 3 * n1[:x]^2 + n2[:x]^2

    JuMP.set_objective_coefficient(graph, n1[:x], n2[:x], 1.0)
    @test objective_function(graph) == 3 * n1[:x]^2 + n2[:x]^2 + n1[:x] * n2[:x]

    JuMP.set_objective_coefficient(graph, [n1[:x], n2[:x]], [n4[:x], n4[:x]], [1.0, 3.0])
    @test objective_function(graph) ==
        3 * n1[:x]^2 + n2[:x]^2 + n1[:x] * n2[:x] + n1[:x] * n4[:x] + 3 * n2[:x] * n4[:x]

    # nonlinear objective
    JuMP.set_objective_function(graph, n1[:x]^3 + n2[:x]^3)
    # NOTE: comparison doesn't seem to work with nonlinear expressions
    # @test objective_function(graph) == n1[:x]^3.0 + n2[:x]^3.0

    # node objectives
    @objective(n1, Min, n1[:x])
    @objective(n2, Max, n2[:x])
    @objective(n3, Min, n3[:x][1]^2 + n3[:x][2]^2)
    @objective(n4, Min, n4[:x]^2)

    set_to_node_objectives(graph)
    @test objective_function(graph) ==
        n1[:x] - n2[:x] + n3[:x][1]^2 + n3[:x][2]^2 + n4[:x]^2

    JuMP.set_objective_function(n1, n1[:y])
    JuMP.set_objective_sense(n1, MOI.MAX_SENSE)
    set_to_node_objectives(graph)
    @test objective_function(graph) ==
        -n1[:y] - n2[:x] + n3[:x][1]^2 + n3[:x][2]^2 + n4[:x]^2

    @objective(n4, Min, n4[:x]^3)
    set_to_node_objectives(graph)
    @test typeof(objective_function(graph)) == GenericNonlinearExpr{RemoteVariableRef}

    # test solve
    set_optimizer(graph, optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0))
    JuMP.optimize!(graph)
    @test JuMP.termination_status(graph) == MOI.LOCALLY_SOLVED
end

function test_subgraphs()
    
    graph = RemoteOptiGraph(worker = 2; name=:root)

    @optinode(graph, n0)
    @variable(n0, x)

    sg1 = _create_test_nonlinear_optigraph()
    sg2 = _create_test_nonlinear_optigraph()
    add_subgraph(graph, sg1)
    add_subgraph(graph, sg2)

    n11, n12, n13, n14 = all_nodes(sg1)
    n21, n22, n23, n24 = all_nodes(sg2)

    # link constraints
    @linkconstraint(graph, n0[:x] + n11[:x] + n21[:x] <= 10)
    @linkconstraint(graph, n12[:x] == n24[:x])

    @test num_local_nodes(graph) == 1
    @test num_nodes(graph) == 9
    @test num_local_edges(graph) == 2
    @test num_remote_edges(graph) == 8
    @test num_edges(graph) == 2
    @test num_subgraphs(graph) == 2

    # constraints
    @test num_local_constraints(graph) == 0
    @test length(local_constraints(graph)) == 0
    @test num_constraints(graph, count_variable_in_set_constraints=true) == 118
    @test length(all_constraints(graph, include_variable_in_set_constraints=true)) == 118

    con_types = list_of_constraint_types(graph)
    F, S = con_types[5]

    # link constraints
    @test num_local_remote_link_constraints(graph, F, S) == 0
    @test num_remote_link_constraints(graph, F, S) == 52
    @test num_local_link_constraints(graph) == 2
    @test num_remote_link_constraints(graph) == 58
    @test length(local_remote_link_constraints(graph, F, S)) == 0
    @test length(all_remote_link_constraints(graph, F, S)) == 52
    @test length(local_remote_link_constraints(graph)) == 0
    @test length(all_remote_link_constraints(graph)) == 58

    F = GenericAffExpr{Float64, RemoteVariableRef}
    @test num_local_link_constraints(graph, F, S) == 1
    @test length(local_link_constraints(graph, F, S)) == 1
    @test num_link_constraints(graph, F, S) == 1
    @test length(local_link_constraints(graph, F, S)) == 1
    @test num_local_link_constraints(graph) == 2
    @test length(local_link_constraints(graph)) == 2
    @test num_link_constraints(graph) == 2
    @test length(all_link_constraints(graph)) == 2

    # set objective
    @objective(sg1, Min, n11[:x] + n12[:x] + n13[:x][1] + n14[:x])
    @objective(sg2, Min, n21[:x] + n22[:x] + n23[:x][1] + n24[:x])

    # optimize subgraphs
    set_optimizer(sg1, optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0))
    optimize!(sg1)
    @test JuMP.termination_status(sg1) == MOI.LOCALLY_SOLVED

    set_optimizer(sg2, optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0))
    optimize!(sg2)
    @test JuMP.termination_status(sg2) == MOI.LOCALLY_SOLVED

    # optimize root graph
    set_optimizer(graph, optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0))
    optimize!(graph)
    @test termination_status(graph) == MOI.LOCALLY_SOLVED

    # check that node solution matches source graph solution
    @test value(n11[:x]) == value(sg1, n11[:x])

    g = RemoteOptiGraph(worker = 2)
    g1 = RemoteOptiGraph(worker = 2)
    g2 = RemoteOptiGraph(worker = 2)

    add_subgraph(g, g1)
    add_subgraph(g1, g2)

    @optinode(g1, n1)
    @variable(n1, x)
    @optinode(g2, n2)
    @variable(n2, y)

    @test get_all_source_graphs(n1) == [g1, g]
    @test get_all_source_graphs(x) == [g1, g]
    @test get_all_source_graphs(n2) == [g2, g1, g]
    @test get_all_source_graphs(y) == [g2, g1, g]
end

function test_variable_constraints()
    
    graph = RemoteOptiGraph(worker = 2)
    set_optimizer(graph, HiGHS.Optimizer)

    @optinode(graph, nodes[1:2])
    n1, n2 = all_nodes(graph)

    @variable(n1, x >= 1)
    @variable(n2, 0 <= x <= 2)

    # parameter
    @variable(n2, p in Parameter(1.0))

    @test parameter_value(p) == 1.0
    set_parameter_value(p, 2.0)
    @test parameter_value(p) == 2.0

    # start value
    set_start_value(n2[:x], 3.0)
    @test start_value(n2[:x]) == 3.0

    # variable not owned
    @test_throws ErrorException @constraint(n2, n1[:x] >= 0)

    # bounds
    @test has_lower_bound(n1[:x]) == true
    @test has_upper_bound(n1[:x]) == false
    @test lower_bound(n1[:x]) == 1
    @test upper_bound(n2[:x]) == 2

    set_lower_bound(n1[:x], 0)
    @test lower_bound(n1[:x]) == 0
    set_upper_bound(n2[:x], 3)
    @test upper_bound(n2[:x]) == 3

    JuMP.set_silent(graph)
    set_optimizer_attribute(graph, "output_flag", false)
    # fix variables
    JuMP.fix(n1[:x], 1; force=true)
    optimize!(graph)
    @test value(n1[:x]) == 1

    JuMP.fix(n1[:x], 2)
    optimize!(graph)
    @test value(n1[:x]) == 2

    JuMP.fix(n1[:x], 0)
    optimize!(graph)
    @test value(n1[:x]) == 0

    # integer and binary
    set_binary(n1[:x])
    @test is_binary(n1[:x]) == true
    optimize!(graph)

    set_integer(n2[:x])
    @test is_integer(n2[:x]) == true
    optimize!(graph)
    
    graph = RemoteOptiGraph(worker = 2)

    @optinode(graph, nodes[1:2])
    n1, n2 = all_nodes(graph)

    @variable(n1, x >= 1)
    @variable(n2, 0 <= x <= 2)

    # set normalized coefficients
    @variable(n1, y >= 0)
    @constraint(n1, con1, n1[:x] + n1[:y] >= 1)
    @constraint(n1, con2, 2 * n1[:x] + n1[:y] >= 1)
    @linkconstraint(graph, link_con1, n1[:x] + n2[:x] >= 0)
    @linkconstraint(graph, link_con2, n1[:y] * n2[:x] >= 0)
    @linkconstraint(graph, link_con3, 2 * n1[:y] * n2[:x] >= 1)

    set_normalized_coefficient(n1[:con1], n1[:x], 2)
    @test normalized_coefficient(n1[:con1], n1[:x]) == 2
    set_normalized_coefficient([n1[:con1], n1[:con2]], [n1[:x], n1[:x]], [3.0, 2.0])
    @test normalized_coefficient(n1[:con1], n1[:x]) == 3
    @test normalized_coefficient(n1[:con2], n1[:x]) == 2
    set_normalized_coefficient(graph[:link_con2], n1[:y], n2[:x], 2.0)
    @test normalized_coefficient(graph[:link_con2], n1[:y], n2[:x]) == 2
    set_normalized_coefficient(
        [graph[:link_con2], graph[:link_con3]],
        [n1[:y], n1[:y]],
        [n2[:x], n2[:x]],
        [3.0, 3.0],
    )
    @test normalized_coefficient(graph[:link_con2], n1[:y], n2[:x]) == 3
    @test normalized_coefficient(graph[:link_con3], n1[:y], n2[:x]) == 3
end

function test_multiple_solves()
    graph = _create_test_nonlinear_optigraph()
    set_optimizer(graph, optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0))
    optimize!(graph)

    n1 = all_nodes(graph)[1]
    set_lower_bound(n1[:x], 1.5)
    optimize!(graph)
    @test isapprox(value(n1[:x]), 1.5, atol=1e-6)

    @linkconstraint(graph, sum(all_variables(graph)) <= 100)
    optimize!(graph)
    @test value(sum(all_variables(graph))) <= 100
    @test termination_status(graph) == MOI.LOCALLY_SOLVED
end

function test_optimizer_attributes()
    graph = _create_test_nonlinear_optigraph()
    set_optimizer(graph, optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0))
    set_optimizer_attribute(graph, "max_cpu_time", 1e2)
    @test get_optimizer_attribute(graph, "max_cpu_time") == 100.0
    return optimize!(graph)
end

function test_nlp_exceptions()
    graph = _create_test_nonlinear_optigraph()
    @test_throws Exception @NLconstraint(graph, graph[1][:x]^3 >= 0)
end

function test_delete_extensions()
    graph = RemoteOptiGraph(worker = 2)
    @optinode(graph, nodes[1:2])

    @variable(nodes[1], x >= 1)
    @variable(nodes[2], x >= 2)
    @constraint(nodes[1], n_con, nodes[1][:x]^2 >= 1)
    @linkconstraint(graph, l_con, nodes[1][:x] + nodes[2][:x] == 4)

    edge = JuMP.owner_model(l_con)

    @test_throws ErrorException JuMP.delete(edge, n_con)
    @test_throws ErrorException JuMP.delete(nodes[1], l_con)

    JuMP.delete(nodes[1], n_con)
    @test !(n_con in all_constraints(nodes[1]))
    JuMP.delete(edge, l_con)
    @test !(l_con in all_link_constraints(graph))
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

TestRemoteOptiGraph.run_tests()

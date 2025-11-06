#  Copyright 2021, Jordan Jalving, Yankai Cao, Victor Zavala, and contributors
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at https://mozilla.org/MPL/2.0/.

module TestAggregatation

using Plasmo
using Ipopt
using JuMP
using Test

function _create_test_optigraph()
    graph = OptiGraph()
    @optinode(graph, nodes[1:10])
    for node in nodes
        @variable(node, 0 <= x <= 2)
        @variable(node, 0 <= y <= 3)
        @constraint(node, x + y >= 0)
        @constraint(node, x^2 + y^2 <= 10)
        @constraint(node, x^3 + y <= 4)
    end
    @linkconstraint(graph, links[i=1:9], nodes[i][:x] == nodes[i + 1][:x])
    @objective(graph, Min, sum(node[:y] for node in nodes))
    return graph
end

function _create_nested_test_optigraph()
    graph = OptiGraph()
    for _ in 1:4
        add_subgraph(graph, _create_test_optigraph())
    end
    subs = local_subgraphs(graph)
    for i in 1:3
        @linkconstraint(graph, subs[i + 1][1][:x] == subs[i][10][:x])
    end
    return graph
end

function _create_test_model()
    model = Model()
    @variable(model, x[1:10] >= 0)
    @variable(model, y[1:5] >= 2)
    @constraint(model, cons[j=1:5], x[j] + y[j] <= 10)
    @constraint(model, sum_con_ref, sum(x) <= y[1]^4)
    @objective(model, Min, sum(x) + sum(y)^3)
    return model
end

function test_aggregate_solution()
    graph = _create_test_optigraph()
    agg_node, ref_map = aggregate(graph)

    set_optimizer(graph, optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0))
    optimize!(graph)

    agg_graph = set_optimizer(
        agg_node, optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0)
    )
    optimize!(agg_graph)

    @test objective_value(agg_graph) == objective_value(graph)
    @test value.(agg_graph, all_variables(agg_graph)) == value.(graph, all_variables(graph))
end

function test_set_model()
    m = _create_test_model()

    graph = OptiGraph()
    n1 = add_node(graph)
    set_jump_model(n1, m)

    set_optimizer(m, optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0))
    optimize!(m)

    set_optimizer(graph, optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0))
    set_to_node_objectives(graph)
    optimize!(graph)

    @test objective_value(m) == objective_value(graph, n1)
    @test value.(all_variables(m)) == value.(graph, all_variables(n1))

    node_vars = all_variables(n1)
    @test n1[:x] == node_vars[1:10]
    @test n1[:y] == node_vars[11:15]
    @test (n1, :cons) in keys(Plasmo.node_object_dictionary(n1))
    @test (n1, :sum_con_ref) in keys(Plasmo.node_object_dictionary(n1))
end

function test_aggregate_to_depth()
    graph = _create_nested_test_optigraph()
    agg_graph, ref_map = aggregate_to_depth(graph, 0; name=:agg_graph)
    @test num_nodes(agg_graph) == 4
    @test num_edges(agg_graph) == 3
    @test num_subgraphs(agg_graph) == 0
    @test num_variables(agg_graph) == 80
    @test num_constraints(agg_graph, count_variable_in_set_constraints = true) == 319
    @test num_local_link_constraints(agg_graph) == 3
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

end #module

TestAggregatation.run_tests()

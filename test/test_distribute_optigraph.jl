#  Copyright 2021, Jordan Jalving, Yankai Cao, Victor Zavala, and contributors
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at https://mozilla.org/MPL/2.0/.

using Plasmo
using Ipopt
using HiGHS
using Suppressor
using Test
using Distributed
using DistributedArrays

if nprocs() < 2
    addprocs(1)
end
@everywhere begin
    using Plasmo, Ipopt, HiGHS, Suppressor, Test, Distributed, DistributedArrays
end
module TestDistributeOptiGraph

using Plasmo
using Ipopt
using HiGHS
using Suppressor
using Test

function _create_test_graph()
    graph = OptiGraph()

    @optinode(graph, n1)
    @optinode(graph, n2)
    @optinode(graph, n3)
    @optinode(graph, n4)

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

function test_distribute_optigraph()

    g = OptiGraph()
    g1 = _create_test_graph()
    g2 = _create_test_graph()
    g3 = _create_test_graph()

    add_subgraph(g, g1)
    add_subgraph(g, g2)
    add_subgraph(g, g3)

    @linkconstraint(g, lc1, g1[:n1][:x] + g2[:n1][:x] <= 1)
    @linkconstraint(g, lc2, g1[:n1][:y] + g3[:n2][:x] >= -2)
    @linkconstraint(g, lc3, g2[:n2][:y] - g3[:n1][:x] == 0)

    workers = [2,2,2]

    rg = Plasmo.distribute_graph(g, workers)
    subgraphs = local_subgraphs(g)
    rsubgraphs = local_subgraphs(rg)
    @test length(local_subgraphs(g)) == length(local_subgraphs(rg))
    @test num_variables(rsubgraphs[1]) == num_variables(subgraphs[1])
    @test num_variables(rg) == num_variables(g)
    @test num_constraints(rg) == num_constraints(g)

    @test length(local_edges(g)) == length(local_edges(rg))
    redge_con1 = constraint_object(all_constraints(all_edges(rg)[1])[1])
    redge_con2 = constraint_object(all_constraints(all_edges(rg)[2])[1])
    redge_con3 = constraint_object(all_constraints(all_edges(rg)[3])[1])

    @test redge_con1.set == constraint_object(lc1).set
    @test redge_con2.set == constraint_object(lc2).set
    @test redge_con3.set == constraint_object(lc3).set
    @test length(redge_con1.func) == length(constraint_object(lc1).func)
    @test length(redge_con2.func) == length(constraint_object(lc2).func)
    @test length(redge_con3.func) == length(constraint_object(lc3).func)
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

TestDistributeOptiGraph.run_tests()

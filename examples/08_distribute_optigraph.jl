a=1

using Plasmo
using Distributed
using DistributedArrays
using JuMP
using HiGHS
using Ipopt

if nprocs() == 1
    addprocs(1)
end

@everywhere begin
    using Plasmo, JuMP, Distributed, HiGHS, Ipopt, DistributedArrays
end

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


# dev file for subgraphs; different backends
using Plasmo
using HiGHS

graph = OptiGraph(; name=:g1)

# subgraph1
sg1 = Plasmo.add_subgraph(graph; name=:sg1)

# node 1
n1 = Plasmo.add_node(sg1)
@variable(n1, x >= 0)
@variable(n1, y >= 0)
@constraint(n1, ref1, n1[:x]+ n1[:y] <= 10)

#node 2
n2 = Plasmo.add_node(sg1)
@variable(n2, x >= 1)
@variable(n2, y >= 2)
@constraint(n2, ref2, n2[:x] + n2[:y] <= 4)


# linking constraint on subgraph1
edge1 = Plasmo.add_edge(sg1, n1, n2)
@constraint(edge1, ref_edge_1, n1[:x] == n2[:x])

# subgraph 2
sg2 = Plasmo.add_subgraph(graph; name=:sg2)

# node 3
n3 = Plasmo.add_node(sg2)
@variable(n3, x >= 0)
@variable(n3, y >= 0)
@constraint(n3, ref3, n3[:x] + n3[:y] <= 10)

#node 4
n4 = Plasmo.add_node(sg2)
@variable(n4, x >= 1)
@variable(n4, y >= 2)
@constraint(n4, ref4, n4[:x] + n4[:y] <= 4)

# linking constraint on subgraph2
edge2 = Plasmo.add_edge(sg2, n3, n4)
@constraint(edge2, ref_edge_2, n3[:x] == n4[:x])

# link across subgraphs
edge3 = Plasmo.add_edge(graph, n2, n4)
@constraint(edge3, ref_edge_3, n2[:y] == n4[:y])


# optimize subgraph1
@objective(sg1, Min, n1[:x] + n2[:y])
set_optimizer(sg1, HiGHS.Optimizer)
optimize!(sg1)

# optimize subgraph2
@objective(sg2, Min, n3[:x] + n4[:y])
set_optimizer(sg2, HiGHS.Optimizer)
optimize!(sg2)


# optimize complete graph
# @objective(graph, Max, n1[:x] + n2[:x] + n3[:x] + n4[:x])
# set_optimizer(graph, HiGHS.Optimizer)
# optimize!(graph)



# @show value(n1[:x])
# @show value(n2[:x])
# @show value(n3[:x])
# @show value(n4[:x])
# @show value(n2[:y])
# @show value(n4[:y])

# println(objective_value(graph))

# Plasmo._append_node_to_backend!(graph, n1)
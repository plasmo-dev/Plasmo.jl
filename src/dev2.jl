# dev file for subgraphs

using Plasmo
using HiGHS

graph = OptiGraph(; name=:g1)

sg1 = Plasmo.add_subgraph(graph; name=:sg1, optimizer_graph=graph)

# node 1
n1 = Plasmo.add_node(sg1)
@variable(n1, x >= 0)
@variable(n1, y >= 0)
@constraint(n1, ref1, x+y <= 10)

#node 2
n2 = Plasmo.add_node(sg1)
@variable(n2, x >= 1)
@variable(n2, y >= 2)
@constraint(n2, ref2, x+y <= 4)

# linking constraint
edge1 = Plasmo.add_edge(sg1, n1, n2)
@constraint(edge1, ref_edge_1, n1[:x] == n2[:x])

sg2 = Plasmo.add_subgraph(graph; name=:sg2)

# node 3
n3 = Plasmo.add_node(sg2)
@variable(n3, x >= 0)
@variable(n3, y >= 0)
@constraint(n3, ref3, x+y <= 10)

#node 4
n4 = Plasmo.add_node(sg2)
@variable(n4, x >= 1)
@variable(n4, y >= 2)
@constraint(n2, ref4, x+y <= 4)

# linking constraint
edge2 = Plasmo.add_edge(sg2, n3, n4)
@constraint(edge2, ref3, n3[:x] == n4[:x])



@objective(graph, Min, n1[:x] + n2[:x] + n3[:x] + n4[:x])

obj = objective_function(graph)


# TODO: 
#@linkconstraint(graph, n1[:x] + n2[:x] == 2)

# TODO:
set_optimizer(graph, HiGHS.Optimizer)
optimize!(graph)
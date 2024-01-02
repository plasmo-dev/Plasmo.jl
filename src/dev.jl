using Plasmo
graph = OptiGraph(;label=:g1)

n1 = Plasmo.add_node(graph)
@variable(n1, x >= 0)
@variable(n1, y >= 0)
@constraint(n1, ref1, x+y==2)

n2 = Plasmo.add_node(graph)
@variable(n2, x >= 1)
@variable(n2, y >= 2)
@constraint(n2, ref2, x+y==4)

edge1 = Plasmo.add_edge(graph, n1, n2)

@constraint(edge1, ref3, n1[:x] == n2[:x])

@objective(graph, Min, n1[:x] + n2[:x])

# TODO
#@linkconstraint(graph, n1[:x] + n2[:x] == 2)


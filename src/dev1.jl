using Plasmo
using HiGHS

graph = OptiGraph(; name=:g1)

n1 = Plasmo.add_node(graph)
@variable(n1, x >= 0)
@variable(n1, y >= 0)
@constraint(n1, ref1, x+y <= 10)

n2 = Plasmo.add_node(graph)
@variable(n2, x >= 1)
@variable(n2, y >= 2)
@constraint(n2, ref2, x+y <= 4)

# linking constraint
edge1 = Plasmo.add_edge(graph, n1, n2)
@constraint(edge1, ref3, n1[:x] == n2[:x])

@objective(graph, Min, n1[:x] + n2[:x])

obj = objective_function(graph)


# TODO: 
#@linkconstraint(graph, n1[:x] + n2[:x] == 2)

# TODO:
set_optimizer(graph, HiGHS.Optimizer)
optimize!(graph)

# TODO: nonlinear

# TODO: build backend from multiple graphs

# TODO: hypergraph interface
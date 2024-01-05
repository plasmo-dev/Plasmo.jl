using Plasmo
# using HiGHS
using Ipopt

graph = OptiGraph(; name=:g1)

n1 = Plasmo.add_node(graph)
@variable(n1, x >= 0)
@variable(n1, y >= 0)
@constraint(n1, ref1, x+y <= 10)

# TODO: quadratic functions
@constraint(n1, refq, x^2 + y^2 <= 2)

n2 = Plasmo.add_node(graph)
@variable(n2, x >= 1)
@variable(n2, y >= 2)
@constraint(n2, ref2, x+y <= 4)

# linking constraint
edge1 = Plasmo.add_edge(graph, n1, n2)
@constraint(edge1, ref3a, n1[:x] == n2[:x])
@constraint(edge1, ref3b, n1[:x]^2 + n2[:x]^2 <= 3)

#@objective(graph, Min, n1[:x] + n2[:x])# + n2[:x]^2)

@objective(graph, Min, n1[:x]^2 + n2[:x]^2)

obj = objective_function(graph)

# TODO linkconstraint macro: 
# @linkconstraint(graph, n1[:x] + n2[:x] == 2)

# TODO: nonlinear functions
# @constraint(n1, )

# TODO: build backend from multiple graphs

# TODO: hypergraph interface

# set_optimizer(graph, HiGHS.Optimizer)
set_optimizer(graph, Ipopt.Optimizer)
optimize!(graph)
using Plasmo
using Ipopt

graph = OptiGraph(; name=:g1)

n1 = Plasmo.add_node(graph)
@variable(n1, x >= 0)
@variable(n1, y >= 0)
@constraint(n1, ref1, x+y <= 10)
@constraint(n1, refq, x^2 + y^2 <= 2)

n2 = Plasmo.add_node(graph)
@variable(n2, x >= 1)
@variable(n2, y >= 2)
@constraint(n2, ref2, x+y <= 4)
@constraint(n2, nlref, x^3 + y <= 10)

# add external function
f(x::Real) = x^2
@operator(graph, op_f, 1, f)
@expression(graph, z, op_f(x))

# linking constraint
edge1 = Plasmo.add_edge(graph, n1, n2)
@constraint(edge1, ref3a, n1[:x] == n2[:x])
@constraint(edge1, ref3b, n1[:x]^2 + n2[:x]^2 <= 3)
@constraint(edge1, ref3c, n1[:x]^3 + n2[:x]^3 <= 10)

# quadratic objective
# @objective(graph, Min, n1[:x]^2 + n2[:x]^2)
# obj = objective_function(graph)

# nonlinear objective
@objective(graph, Min, n1[:x]^3 + n2[:x]^2)
obj = objective_function(graph)

# # TODO linkconstraint macro: 
# # @linkconstraint(graph, n1[:x] + n2[:x] == 2)

set_optimizer(graph, Ipopt.Optimizer)
Plasmo.optimize!(graph)
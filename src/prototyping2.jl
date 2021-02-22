#TODO: LinkConstraints into an MOI backend
#Meta-algorithms would still use LinkingConstraints on the algorithm side
#LinkingConstraint --> ScalarConstraint

using Plasmo
using MathOptInterface
using Ipopt
using DataStructures

const MOI = MathOptInterface

graph = OptiGraph()
set_optimizer(graph,Ipopt.Optimizer)

@optinode(graph,n1)
@variable(n1,x[1:5] >= 2)
@variable(n1,y[1:5] >= 1)
@constraint(n1,ref1,sum(x) == 10)
@constraint(n1,ref2,sum(y) == 5)
#@objective(n1,Min,sum(x))

@optinode(graph,n2)
@variable(n2,x[1:5] >= 0)
@variable(n2,y[1:5] >= 1)
@constraint(n2,sum(y[1:5]) + sum(x[1:5]) == 10)
#@objective(n2,Min,sum(x))

@linkconstraint(graph,n1[:x][1] == n2[:x][1])

#TODO Graph objective function
@objective(graph,Min,sum(n1[:x]) + sum(n2[:x])^2)

# Plasmo._aggregate_backends!(graph)
# Plasmo._set_backend_objective(graph)
# back = JuMP.backend(graph)
# T = MOI.get(back,MOI.ObjectiveFunctionType())
# obj = MOI.get(back,MOI.ObjectiveFunction{T}())

optimize!(graph)

println(value.(n1[:x]))
println(value.(n2[:y]))
println(dual(ref1))
println(dual(ref2))

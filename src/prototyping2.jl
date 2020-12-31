#TODO: LinkConstraints into an MOI backend
#Meta-algorithms would still use LinkingConstraints on the algorithm side
#LinkingConstraint --> ScalarConstraint

using Plasmo
using MathOptInterface
using Ipopt
using DataStructures

const MOI = MathOptInterface
const MOIB = MathOptInterface.Bridges
include("moi.jl")

graph = OptiGraph()
set_optimizer(graph,Ipopt.Optimizer)

@optinode(graph,n1)
@variable(n1,x[1:5] >= 2)
@variable(n1,y[1:5] >= 1)
@constraint(n1,ref1,sum(x) == 10)
@constraint(n1,ref2,sum(y) == 5)
@objective(n1,Min,sum(x))


@optinode(graph,n2)
@variable(n2,x[1:5] >= 0)
@variable(n2,y[1:5] >= 1)
@constraint(n2,sum(y[1:5]) + sum(x[1:5]) == 10)
@objective(n2,Min,sum(x))

@linkconstraint(graph,n1[:x][1] == n2[:x][1])

#TODO
#set_sum_of_objectives(graph)

optimize!(graph)

println(value.(n1[:x]))
println(value.(n2[:y]))

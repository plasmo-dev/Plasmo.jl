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

#TODO: @NLconstraint(n1)


@objective(n1,Min,sum(x))

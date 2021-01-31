#Prototyping for NLP Evaluator

using Plasmo
using JuMP
using MathOptInterface
using Ipopt
using DataStructures

const MOI = MathOptInterface

graph = OptiGraph()
#set_optimizer(graph,Ipopt.Optimizer)

@optinode(graph,n1)
@variable(n1,x[1:5] >= 2)
@variable(n1,y[1:5] >= 1)
@constraint(n1,ref1,sum(x) == 10)
@constraint(n1,ref2,sum(y) == 5)
@NLconstraint(n1,nlref,x[1]^2 + x[2]^2 <= 5)
@NLobjective(n1,Min,sum(n1[:x][i] for i = 1:5)^3)

@optinode(graph,n2)
@variable(n2,x[1:5] >= 2)
@variable(n2,y[1:5] >= 1)
@constraint(n2,ref1,sum(x) == 10)
@constraint(n2,ref2,sum(y) == 5)
@NLconstraint(n2,x[1]^2 + x[2]^2 <= 5)
@objective(n2,Min,sum(n2[:x][i] for i = 1:5))
#@NLobjective(n2,Min,sum(n2[:x][i] for i = 1:5)^3)

@linkconstraint(graph,[i = 1:5],n1[:y][i] == n2[:y][i])

d = Plasmo.OptiGraphNLPEvaluator(graph)
MOI.initialize(d,[:Hess,:Jac])

#TODO: someday. #This is an error for now.  It is hard to inspect nonlinear data, but not impossible. We require the objective to be set per node if nonlinear.
#@NLobjective(graph,Min,sum(n1[:x][i] for i = 1:5)^3 + sum(n2[:x][i] for i = 1:5)^3)


#optimize!(graph)
#We need to setup the NLPBlock and point to our evaluator
#Merge MOI.NLPBlock objects and point back to OptiGraphNLPEvaluator

#########################################################
#JuMP version to check Evaluator functions
#########################################################
model = Model()

#"Node 1"
@variable(model,x1[1:5] >= 2)
@variable(model,y1[1:5] >= 1)
@constraint(model,ref11,sum(x1) == 10)
@constraint(model,ref12,sum(y1) == 5)
@NLconstraint(model,x1[1]^2 + x1[2]^2 <= 5)

#"Node 2"
@variable(model,x2[1:5] >= 2)
@variable(model,y2[1:5] >= 1)
@constraint(model,ref1,sum(x2) == 10)
@constraint(model,ref2,sum(y2) == 5)
@NLconstraint(model,x2[1]^2 + x2[2]^2 <= 5)

#"Link Constraint"
@constraint(model,[i = 1:5],y1[i] == y2[i])

#This sets local objective functions on the corresponding nodes?
@NLobjective(model,Min,sum(x1[i] for i = 1:5)+ sum(x2[i] for i = 1:5))
# @objective(model,Min,sum(x1[i] for i = 1:5)+ sum(x2[i] for i = 1:5))
#@NLobjective(model,Min,sum(x1[i] for i = 1:5)^3 + sum(x2[i] for i = 1:5)^3)

d = JuMP.NLPEvaluator(model)
MOI.initialize(d,[:Jac])

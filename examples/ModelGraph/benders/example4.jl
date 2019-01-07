using JuMP
using GLPKMathProgInterface
using Plasmo

mp = Model(solver = GLPKSolverLP())
sp1 = Model(solver = GLPKSolverLP())
sp2 = Model(solver = GLPKSolverLP())
sp3 = Model(solver = GLPKSolverLP())

@variable(mp,x[1:2]>=0)
@variable(sp1,y[1:2]>=0)
@variable(sp2,z[1:2]>=0)
@variable(sp3,t[1:2]>=0)
@constraint(mp,x[1]+x[2]>=27)
@objective(mp,Min, 3x[1]+2x[2])

@variable(sp1,x[1:2]>=0)
@constraint(sp1,x[1]+y[2]>=34)
@constraint(sp1,x[2]+y[1]>=52)
@objective(sp1,Min, 4y[1]+6y[2])

@variable(sp2,x[1:2]>=0)
@constraint(sp2,x[1]+z[2]>=61)
@constraint(sp2,x[2]+z[1]>=29)
@objective(sp2,Min, 7z[1]+8z[2])

@variable(sp3,x[1:2]>=0)
@constraint(sp3,x[1]+t[2]>=43)
@constraint(sp3,x[2]+t[1]>=75)
@objective(sp3,Min, 10t[1]+5t[2])

g = ModelTree()
setsolver(g, BendersSolver(lp_solver = GLPKSolverLP()))
n1 = add_node(g,level = 1)
n2 = add_node(g,level = 2)
n3 = add_node(g, level = 2)
n4 = add_node(g, level = 2)

setmodel(n1, mp)
setmodel(n2, sp1)
setmodel(n3, sp2)
setmodel(n4, sp3)

@linkconstraint(g,[i in 1:2], n1[:x][i] == n2[:x][i])
@linkconstraint(g,[i in 1:2], n1[:x][i] == n3[:x][i])
@linkconstraint(g,[i in 1:2], n1[:x][i] == n4[:x][i])

result = solve(g,max_iterations = 10)
#bendersolve(g,max_iterations = 10)

using JuMP
using GLPKMathProgInterface
using Plasmo

## Model from Fisher,1985. An Applications Oriented Guide to Lagrangian Relaxation
# Max 16x[1] + 10x[2] + 4y[2]
# s.t. x[1] + x[2] <= 1
#      y[1] + y[2] <= 1
#      8x[1] + 2x[2] + y[1] + 4y[2] <= 10
#      x, y ∈ {0,1}

## Model on x
# Min 16x[1] + 10x[2]
# s.t. x[1] + x[2] <= 1OutputFlag=0
#      x ∈ {0,1}
#m1 = Model(solver=GurobiSolver(OutputFlag=0))
m1 = Model(solver=GLPKSolverMIP())

@variable(m1, xm[i in 1:2],Bin)
@constraint(m1, xm[1] + xm[2] <= 1)
@objective(m1, Max, 16xm[1] + 10xm[2])

## Model on y`
# Max  4y[2]
# s.t. y[1] + y[2] <= 1
#      8x[1] + 2x[2] + y[1] + 4y[2] <= 10
#      x, y ∈ {0,1}

#m2 = Model(solver=GurobiSolver(OutputFlag=0))
m2 = Model(solver=GLPKSolverMIP())
@variable(m2, xs[i in 1:2],Bin)
@variable(m2, y[i in 1:2], Bin)
@constraint(m2, y[1] + y[2] <= 1)
@constraint(m2, 8xs[1] + 2xs[2] + y[1] + 4y[2] <= 10)
@objective(m2, Max, 4y[2])

## Model Graph
graph = ModelGraph()
heur(g) = 16
setsolver(graph, LagrangeSolver(update_method=:subgradient,max_iterations=30,lagrangeheuristic=heur))
n1 = add_node(graph)
setmodel(n1,m1)
n2 = add_node(graph)
setmodel(n2,m2)

## Linking
# m1[x] = m2[x]  ∀i ∈ {1,2}
@linkconstraint(graph, [i in 1:2], n1[:xm][i] == n2[:xs][i])

solution = solve(graph)

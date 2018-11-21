using JuMP
using Gurobi
using Plasmo
using PlasmoAlgorithms

##Place MP and SP into ModelGraph
mp = Model(solver = GurobiSolver(OutputFlag=0))
sp = Model(solver = GurobiSolver(OutputFlag=0))

@variable(mp,y>=0)
@objective(mp,Min,2y)

@variable(sp,x[1:2]>=0)
@variable(sp,y>=0)
@constraint(sp,c1,2x[1]-x[2]+3y>=4)
@constraint(sp,x[1]+2x[2]+y>=3)
@objective(sp,Min,2x[1]+3x[2])

## Plasmo Graph
g = ModelGraph()
setsolver(g, GurobiSolver(OutputFlag=0))
n1 = add_node(g)
setmodel(n1,mp)
n2 = add_node(g)
setmodel(n2,sp)

##Set n2 as a child node of n1
edge = Plasmo.add_edge(g,n1,n2)

## Linking constraints between MP and SP
@linkconstraint(g, n1[:y] == n2[:y])

bendersolve(g, max_iterations=5)

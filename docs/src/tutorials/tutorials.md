# Tutorials

## Convert `ModelGraph` to JuMP `Model`

```julia
using JuMP
using Plasmo
using Ipopt

graph = ModelGraph()
setsolver(graph,Ipopt.IpoptSolver())

#Add nodes to a GraphModel
n1 = add_node(graph)
n2 = add_node(graph)

m1 = JuMP.Model()
@variable(m1,0 <= x <= 2)
@variable(m1,0 <= y <= 3)
@constraint(m1,x+y <= 4)
@objective(m1,Min,x)

m2 = Model()
@variable(m2,x)
@NLconstraint(m2,exp(x) >= 2)


#Set models on nodes and edges
setmodel(n1,m1)     #set m1 to node 1.  Updates reference on m1
setmodel(n2,m2)

#Link constraints take the same expressions as the JuMP @constraint macro
@linkconstraint(graph,n1[:x] == n2[:x])

#Get all of the link constraints in a graph
links = getlinkconstraints(graph)
for link in links
    println(link)
end

jump_model = create_jump_graph_model(graph)
jump_model.solver = IpoptSolver()

solve(jump_model)

links = getlinkconstraints(jump_model)

getdual(links[1])
```
## Using the `LagrangeSolver`

```julia
using JuMP
using GLPKMathProgInterface
using Plasmo

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
```

# Simple Plasmo Example

Plasmo.jl uses JuMP to create component models in a ModelGraph.  JuMP models are associated with nodes and can have their variables connected to other nodes (models) with linkconstraints.
The below script demonstrates solving a nonlinear optimization problem containing two nodes with a simple link constraint between them and solving with Ipopt.


```julia
using JuMP
using Plasmo
using Ipopt

graph = ModelGraph()
setsolver(graph,IpoptSolver())

#Add nodes to a ModelGraph
n1 = add_node!(graph)
n2 = add_node!(graph)

#Create JuMP models
m1 = Model()
@variable(m1,0 <= x <= 2)
@variable(m1,0 <= y <= 3)
@constraint(m1,x+y <= 4)
@objective(m1,Min,x)

m2 = Model()
@variable(m2,x)
@NLconstraint(m2,exp(x) >= 2)

#Set JuMP models on nodes
setmodel(n1,m1)     #set m1 to node 1.  Updates reference on m1
setmodel(n2,m2)

#Link constraints take the same expressions as the JuMP @constraint macro
@linkconstraint(graph,n1[:x] == n2[:x])

#Get all of the link constraints in a graph
links = getlinkconstraints(graph)

solve(graph)

println("n1[:x]= ",JuMP.getvalue(n1[:x]))
println("n2[:x]= ",JuMP.getvalue(n2[:x]))
```

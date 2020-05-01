# Simple Plasmo Example

Plasmo.jl uses modelnodes to construct modular optimization models that have their variables coupled to other modelnodes with linkconstraints.
The below script demonstrates solving a nonlinear optimization problem containing two modelnodes with a simple linkconstraint with Ipopt.

```julia
using Plasmo
using Ipopt

graph = ModelGraph()

#Add nodes to a ModelGraph
@node(graph,n1)
@node(graph,n2)

@variable(n1,0 <= x <= 2)
@variable(n1,0 <= y <= 3)
@constraint(n1,x+y <= 4)
@objective(n1,Min,x)

@variable(n2,x)
@NLnodeconstraint(n2,exp(x) >= 2)

#Add a linkconstraint
@linkconstraint(graph,n1[:x] == n2[:x])


ipopt = Ipopt.Optimizer
optimize!(graph,ipopt)

println("n1[:x]= ",value(n1,n1[:x]))
println("n2[:x]= ",value(n2,n2[:x]))
```

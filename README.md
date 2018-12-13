![Plasmo](docs/Plasmo.svg)

# Plasmo.jl
Plasmo.jl is a graph-based modeling interface for optimization problems.  It facilitates component modeling by modularizing individual optimization models which can be connected using linking constraints.  Optimization models can be associated with both nodes and edges within a PlasmoGraph which facilitates modeling physical networks, or a collection of nodes can simply be connected through link constraints.  It is also possible to define multiple subgraphs within a graph, and create linking constraints between nodes and edges within their respective subgraphs.  This facilitates construction of hierarchical models which can be solved with parallel solvers such as [PIPS-NLP](https://github.com/Argonne-National-Laboratory/PIPS/tree/master/PIPS-NLP) and [DSP](https://github.com/Argonne-National-Laboratory/DSP).
Plasmo.jl been developed by the [Scalable Systems Laboratory](http://zavalab.engr.wisc.edu/) at the University of Wisconsin-Madison.
The primary developers are Jordan Jalving(@jalving) and Yankai Cao (@YankaiCao), with notable input from the JuMP development community.

# Installation

```julia
Pkg.clone("https://github.com/jalving/Plasmo.jl")
```

# Simple Example

Plasmo.jl currently supports optimization models written with JuMP.

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

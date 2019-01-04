![Plasmo logo](assets/plasmo.svg)

# Plasmo.jl - Platform for Scalable Modeling and Optimization

Plasmo.jl is a modeling and optimization interface for constructing and solving optimization problems that exploits a graph-aware structure.
The package provides modular model building for optimization problems and graph analysis capabilities that the enable the use of decomposition-based solvers.

## Installation

Plasmo.jl is a [Julia](https://julialang.org) package developed for Julia 1.0.
From Julia, Plasmo is installed by using the built-in package manager:
```julia
import Pkg
Pkg.clone("https://github.com/jalving/Plasmo.jl")
```

or alternatively from the Julia 1.0 package manager, just do

```
] add https://github.com/jalving/Plasmo.jl
```
Plasmo.jl uses [JuMP](https://github.com/JuliaOpt/JuMP.jl) as modeling interface which can be installed with

```julia
import Pkg
Pkg.add("JuMP")
```
or using the Julia package manager
```
] add JuMP
```

## Example Script

Plasmo.jl uses JuMP to create component models in a `ModelGraph`, a graph wherein the nodes are component models.  JuMP models are associated with nodes and can
have their variables linked to other node variables using `LinkConstraints`.
The below script demonstrates solving a nonlinear optimization problem containing two nodes with a simple link constraint and solving with Ipopt.

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
setmodel(n1,m1)     #set m1 to n1
setmodel(n2,m2)

#Link constraints take the same expressions as the JuMP @constraint macro
@linkconstraint(graph,n1[:x] == n2[:x])

#Get all of the link constraints in a model-graph
links = getlinkconstraints(graph)

solve(graph)

#Look at individual node solutions
println("n1[:x]= ",JuMP.getvalue(n1[:x]))
println("n2[:x]= ",JuMP.getvalue(n2[:x]))
```


## Contents

```@contents
Pages = [
    "documentation/modelgraph.md"
    "documentation/graphanalysis.md"
    "documentation/solvers/solvers.md"
    ]
Depth = 2
```


## Index

```@index
```

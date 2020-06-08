![Plasmo logo](assets/plasmo.svg)

# Plasmo.jl - Platform for Scalable Modeling and Optimization

Plasmo.jl is an optimization framework that adopts a modular style to to construct and solve optimization problems.
The package provides tools to build and manage complex model structures and offers partitioning capabilities that facilitate using
or developing decomposition-based solvers.

## Installation

Plasmo.jl is a [Julia](https://julialang.org) package developed for Julia 1.0.
From Julia, Plasmo is installed by using the built-in package manager:
```julia
import Pkg
Pkg.add("Plasmo.jl")
```

or alternatively from the Julia 1.0 package manager, just do

```
] add Plasmo
```

## Example Script

Plasmo.jl uses JuMP to create component models in a `ModelGraph`, a graph wherein the nodes are component models.  JuMP models are associated with nodes and can
have their variables linked to other node variables using `LinkConstraints`.
The below script demonstrates solving a nonlinear optimization problem containing two nodes with a simple link constraint and solving with Ipopt.

```julia
using Plasmo
using Ipopt

graph = OptiGraph()

#Add OptiNodes to an OptiGraph
n1 = @node(graph)
n2 = @node(graph)

#Add node variables
@variable(n1,0 <= x <= 2)
@variable(n1,0 <= y <= 3)
@constraint(n1,x+y <= 4)
@objective(n1,Min,x)

@variable(n2,x)
@NLnodeconstraint(n2,exp(x) >= 2)


#Link constraints
@linkconstraint(graph,n1[:x] == n2[:x])

ipopt = Ipopt.Optimizer
optimize!(graph,ipopt)

#Look at individual node solutions
println("n1[:x]= ",value(n1,n1[:x]))
println("n2[:x]= ",value(n2,n2[:x]))
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

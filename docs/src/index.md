![Plasmo logo](assets/plasmo.svg)

```@meta
CurrentModule = Plasmo
DocTestSetup = quote
    using Plasmo
end
```

# Plasmo.jl - Platform for Scalable Modeling and Optimization

Plasmo.jl is a graph-based optimization framework written in [Julia](https://julialang.org) that adopts a modular modeling style to construct and solve optimization problems.
The package builds upon the modeling framework [JuMP](https://github.com/jump-dev/JuMP.jl) to create graph-structured optimization models and works at a higher level of
abstraction which facilitates hierarchical modeling and graph-based operations such as partitioning.
More specifically, Plasmo.jl implements what is called the `OptiGraph` abstraction to construct optimization models. An `OptiGraph` captures the underlying topology of an
optimization problem using `OptiNodes` (which represent stand-alone optimization models) that are coupled by means of `OptiEdges` (which correspond to coupling constraints). The resulting graph topology
enables systematic model construction and can be exploited for various modeling tasks and the development of distributed optimization algorithms.  

## Installation
The Plasmo.jl package works for Julia versions 1.0 and later.
From Julia, Plasmo.jl can be installed using the built-in package manager:

```julia
import Pkg
Pkg.add("Plasmo")
```
or alternatively from the Julia 1.0 package manager, one can simply do:
```
] add Plasmo
```

## Quickstart Example
This quickstart example gives a brief overview of the functions needed to effectively use Plasmo.jl to build optimization models. If you are familiar with JuMP,
much of the functionality you see here will be equivalent.  In fact, the primary `OptiGraph` object is an extension of the `JuMP.AbstractModel`, as well as its contained `OptiNodes`.  

The below example demonstrates the construction of a simple nonlinear optimization problem that contains two `OptiNodes` coupled by a simple `LinkConstraint` and solved with
the nonlinear optimization solver Ipopt. More detailed examples can be found in the [examples folder](https://github.com/zavalab/Plasmo.jl/tree/master/examples).

Once Plasmo.jl has been installed, you can use it from a Julia session as following:
```jldoctest quickstart_example
julia> using Plasmo
```

For this example we also need to import the Ipopt optimization solver.
```jldoctest quickstart_example
julia> using Ipopt
```
!!! note
    We highlight that it is possible to use any solver that works with JuMP. By default, when using a standard optimization solver available through JuMP, Plasmo.jl will aggregate
    the `OptiGraph` into a single node to solve (hence ignoring the graph structure).  While it is useful having such granular control to build optimization models with an
    `OptiGraph`, we note that this aggregation step introduces additional model-building time when using standard optimization solvers.


The following command will create an `OptiGraph` model:
```jldoctest quickstart_example
julia> graph = OptiGraph()
graph
```

```@example
graph = OptiGraph()

#Add OptiNodes to an OptiGraph
@optinode(graph,n1)
@optinode(graph,n2)

#Setup optinode n1
@variable(n1,0 <= x <= 2)
@variable(n1,0 <= y <= 3)
@constraint(n1,x+y <= 4)
@objective(n1,Min,x)

#Setup optinode n2
@variable(n2,x)
@NLnodeconstraint(n2,exp(x) >= 2)

#Create a linking constraint
@linkconstraint(graph,n1[:x] == n2[:x])

ipopt = Ipopt.Optimizer
optimize!(graph,ipopt) # hide

#Look at individual node solutions
println("n1[:x]= ",value(n1,n1[:x]))
println("n2[:x]= ",value(n2,n2[:x]))
```

## Contents

```@contents
Pages = [
    "documentation/modeling.md"
    "documentation/solvers/partitioning.md"
    "documentation/solvers/solvers.md"
    "documentation/solvers/plotting.md"
    ]
Depth = 2
```

## Index

```@index
```

### Citing Plasmo.jl

If you find Plasmo.jl useful for your work, you may cite the current [pre-print](https://arxiv.org/abs/2006.05378):
``` sourceCode
@misc{JalvingShinZavala2020,
title = {A Graph-Based Modeling Abstraction for Optimization: Concepts and Implementation in Plasmo.jl},
author = {Jordan Jalving and Sungho Shin and Victor M. Zavala},
year = {2020},
eprint = {2006.05378},
archivePrefix = {arXiv},
primaryClass = {math.OC}
}
```

There is also an earlier manuscript where we presented the initial ideas behind Plasmo.jl which you can find
[here](https://www.sciencedirect.com/science/article/abs/pii/S0098135418312687):
``` sourceCode
@article{JalvingCaoZavala2019,
author = {Jalving, Jordan and Cao, Yankai and Zavala, Victor M},
journal = {Computers {\&} Chemical Engineering},
pages = {134--154},
title = {Graph-based modeling and simulation of complex systems},
volume = {125},
year = {2019},
doi = {https://doi.org/10.1016/j.compchemeng.2019.03.009}
}
```
A pre-print of this paper can also be found [here](https://arxiv.org/abs/1812.04983)

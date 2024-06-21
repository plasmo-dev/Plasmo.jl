![Logo](./docs/plasmo3.svg)


[![CI](https://github.com/plasmo-dev/Plasmo.jl/workflows/CI/badge.svg)](https://github.com/plasmo-dev/Plasmo.jl/actions)
[![codecov](https://codecov.io/gh/plasmo-dev/Plasmo.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/plasmo-dev/Plasmo.jl)
[![](https://img.shields.io/badge/docs-latest-blue.svg)](https://plasmo-dev.github.io/Plasmo.jl/dev/)
[![DOI](https://zenodo.org/badge/96967382.svg)](https://zenodo.org/badge/latestdoi/96967382)

# Plasmo.jl

(Platform for Scalable Modeling and Optimization)

Plasmo.jl is a graph-based algebraic modeling framework for building, managing, and solving optimization problems that utilizes graph-theoretic concepts and modular data structures. 
The package extends JuMP.jl to offer concise syntax, interfaces with MathOptInterface.jl to access standard optimization solvers, and utilizes Graphs.jl to provide 
graph analysis and processing methods. Plasmo.jl facilitates developing optimization models for networked systems such as supply chains, power systems, industrial 
processes, or any coupled system that involves multiple components and connections. The package also acts as a high-level platform to develop customized optimization-based decomposition techniques and meta-algorithms to optimize problems over large systems.

## Overview
The core object in Plasmo.jl is the `OptiGraph`, a graph data structure that represents optimization problems as a set of optinodes and optiedges. Optinodes encapsulate variables, expressions, and constraints (and objective functions) as modular models and edges encapsulate linking constraints that couple variables across optinodes. Optigraphs can be embedded within other optigraphs to induce nested hierarchical structures, or they can be partitioned using different graph projections and partitioning algorithms to create new decomposition structures.

## Documentation
The latest documentation is available through [GitHub Pages](https://plasmo-dev.github.io/Plasmo.jl/dev/).
Additional examples can be found in the [examples](https://github.com/plasmo-dev/Plasmo.jl/tree/main/examples) folder.

## Installation

```julia
pkg> add Plasmo
```

## Simple Example

```julia
using Plasmo
using Ipopt

#create an optigraph
graph = OptiGraph()

#add nodes to an optigraph
@optinode(graph,n1)
@optinode(graph,n2)

#add variables and constraints to nodes
@variable(n1, 0 <= x <= 2)
@variable(n1, 0 <= y <= 3)
@constraint(n1, x+y <= 4)

@variable(n2,x)
@constraint(n2, exp(x) >= 2)

#add linking constraints that couple nodes
@linkconstraint(graph, n1[:x] == n2[:x])

# set an optigraph objective
@objective(graph, Min, n1[:x] + n2[:x])

#optimize with Ipopt
set_optimizer(graph, Ipopt.Optimizer)
optimize!(graph)

#Print solution values
println("n1[:x] = ", value(n1[:x]))
println("n2[:x] = ", value(n2[:x]))
```

## Acknowledgments
This code is based on work supported by the following funding agencies:

* U.S. Department of Energy (DOE), Office of Science, under Contract No. DE-AC02-06CH11357
* DOE Office of Electricity Delivery and Energy Reliability’s Advanced Grid Research and Development program at Argonne National Laboratory
* National Science Foundation under award NSF-EECS-1609183 and under award CBET-1748516

The primary developer is Jordan Jalving (@jalving) with support from the following contributors.  

* Victor Zavala (University of Wisconsin-Madison)
* Yankai Cao (University of British Columbia)
* Kibaek Kim (Argonne National Laboratory)
* Sungho Shin (University of Wisconsin-Madison)


## Citing Plasmo.jl

If you find Plasmo.jl useful for your work, you may cite the current [pre-print](https://arxiv.org/abs/2006.05378):

```
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

```
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

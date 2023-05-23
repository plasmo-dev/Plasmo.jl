<img src="https://github.com/plasmo-dev/Plasmo.jl/blob/main/docs/plasmo_logo.svg?raw=true"/>

[![CI](https://github.com/plasmo-dev/Plasmo.jl/workflows/CI/badge.svg)](https://github.com/plasmo-dev/Plasmo.jl/actions)
[![codecov](https://codecov.io/gh/plasmo-dev/Plasmo.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/plasmo-dev/Plasmo.jl)
[![](https://img.shields.io/badge/docs-latest-blue.svg)](https://plasmo-dev.github.io/Plasmo.jl/dev/)
[![DOI](https://zenodo.org/badge/96967382.svg)](https://zenodo.org/badge/latestdoi/96967382)

# Plasmo.jl

[Plasmo.jl](https://github.com/plasmo-dev/Plasmo.jl) (Platform for Scalable Modeling and Optimization) is a graph-based algebraic modeling framework that adopts a modular style to
create mathematical optimization problems and manage distributed and hierarchical structures. The package has been developed as a [JuMP](https://github.com/jump-dev/JuMP.jl) extension and consequently supports 
most JuMP syntax and functions. 

## Overview

The core data structure in Plasmo.jl is the `OptiGraph`. The optigraph contains a set of optinodes which represent self-contained optimization problems and optiedges that represent coupling between optinodes (which produces an underlying [hypergraph](https://en.wikipedia.org/wiki/Hypergraph) structure of optinodes and optiedges). Optigraphs can further be embedded within other optigraphs to create nested hierarchical graph structures. The graph structures obtained using Plasmo.jl can be used for simple model and data management, but they can also be used to perform graph partitioning or develop interfaces to structured optimization solvers.

## License

Plasmo is licensed under the [MPL 2.0 license](https://github.com/plasmo-dev/Plasmo.jl/blob/main/LICENSE.md).

## Installation

Install Plasmo using `Pkg.add`:
```julia
import Pkg
Pkg.add("Plasmo")
```

## Documentation

The latest documentation is available through [GitHub Pages](https://plasmo-dev.github.io/Plasmo.jl/dev/).
Additional examples can be found in the [examples](https://github.com/plasmo-dev/Plasmo.jl/tree/main/examples) folder.

## Simple Example

```julia
using Plasmo
using Ipopt

#create an optigraph
graph = OptiGraph()

#add nodes to an optigraph
@optinode(graph, n1)
@optinode(graph, n2)

#add variables, constraints, and objective functions to nodes
@variable(n1, 0 <= x <= 2)
@variable(n1, 0 <= y <= 3)
@constraint(n1, x+y <= 4)
@objective(n1, Min, x)

@variable(n2,x)
@NLconstraint(n2, exp(x) >= 2)

#add a linkconstraint to couple nodes
@linkconstraint(graph, n1[:x] == n2[:x])

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

If you find Plasmo.jl useful for your work, you may cite the [manuscript](https://link.springer.com/article/10.1007/s12532-022-00223-3) as:
```
@article{JalvingShinZavala2022,
  title={A Graph-Based Modeling Abstraction for Optimization: Concepts and Implementation in Plasmo.jl},
  author={Jordan Jalving and Sungho Shin and Victor M. Zavala},
  journal={Mathematical Programming Computation},
  year={2022},
  volume={14},
  pages={699 - 747}
}
```

There is also a freely available [pre-print](https://arxiv.org/abs/2006.05378):
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

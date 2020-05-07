![Logo](./docs/plasmo3.svg)

[![Build Status](https://travis-ci.org/jalving/Plasmo.jl.svg?branch=master)](https://travis-ci.org/jalving/Plasmo.jl)
[![codecov](https://codecov.io/gh/jalving/Plasmo.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/jalving/Plasmo.jl)
[![coveralls](https://coveralls.io/repos/github/jalving/Plasmo.jl/badge.svg?branch=master)](https://coveralls.io/github/jalving/Plasmo.jl?branch=master)
[![](https://img.shields.io/badge/docs-latest-blue.svg)](https://jalving.github.io/Plasmo.jl/dev/)

# Plasmo.jl
Plasmo.jl (Platform for Scalable Modeling and Optimization) is a graph-based algebraic modeling framework.  It builds upon
JuMP and adopts a modular style to model optimization problems which facilitates creating distributed and hierarchical structures.
The defining notion of the package is that it uses graph-based concepts to both construct and partition optimization problems which
provides a natural interface to implement distributed optimization algorithms.

## Overview
The core object in Plasmo.jl is the `ModelGraph` wherein a user can add `ModelNode`(s) which represent individual optimization problems. `ModelNode`(s) can be linked to each-other
using linkconstraints, which induces the underlying distributed graph structure.  A modelgraph can also be embedded in another modelgraph to induce hierarchical structures.
Such distributed and hierarchical structures provide a natural framework to harness distributed optimization solvers such as [PIPS-NLP](https://github.com/Argonne-National-Laboratory/PIPS/tree/master/PIPS-NLP).

## Documentation
Documentation is available through [GitHub Pages](https://jalving.github.io/Plasmo.jl/dev).
Additional examples can be found in the [examples](https://github.com/jalving/Plasmo.jl/tree/master/examples/ModelGraph) folder.

## Installation

```julia
using Pkg
Pkg.add("Plasmo.jl")
```

## Simple Example

```julia
using Plasmo
using Ipopt

graph = ModelGraph()

#Add nodes to a ModelGraph
@node(graph,n1)
@node(graph,n2)

#Add variables, constraints, and objective functions to nodes
@variable(n1,0 <= x <= 2)
@variable(n1,0 <= y <= 3)
@constraint(n1,x+y <= 4)
@objective(n1,Min,x)

@variable(n2,x)
@NLnodeconstraint(n2,exp(x) >= 2)

#Add a linkconstraint to couple modelnodes
@linkconstraint(graph,n1[:x] == n2[:x])

#Optimize with Ipopt
ipopt = Ipopt.Optimizer
optimize!(graph,ipopt)

#Print solution values
println("n1[:x]= ",value(n1,n1[:x]))
println("n2[:x]= ",value(n2,n2[:x]))
```

## Acknowledgments
This code is based on work supported by the U.S. Department of Energy (DOE), Office of Science, under Contract No. DE-AC02-06CH11357 as well as the DOE Office of Electricity Delivery and Energy Reliability’s Advanced Grid Research and Development program at Argonne National Laboratory. We acknowledge partial support from the National Science Foundation under award NSF-EECS-1609183.
The primary developer is Jordan Jalving (@jalving) with support from the following
contributors.  

* Victor Zavala (UW-Madison)
* Yankai Cao (University of British Columbia)
* Kibaek Kim (ANL)
* Sungho Shin (UW-Madison)


## Citing Plasmo.jl
If you find Plasmo.jl useful for your work, you may cite the following [manuscript](https://www.sciencedirect.com/science/article/abs/pii/S0098135418312687):

```
@article{Jalving2019,
author = {Jalving, Jordan and Cao, Yankai and Zavala, Victor M},
journal = {Computers {\&} Chemical Engineering},
pages = {134--154},
title = {Graph-based modeling and simulation of complex systems},
volume = {125},
year = {2019},
doi = {https://doi.org/10.1016/j.compchemeng.2019.03.009}
}
```

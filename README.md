![Logo](./docs/plasmo.svg)

# Plasmo.jl
Plasmo.jl is a graph-based modeling interface that facilitates modeling and solving optimization problems over physical systems.  
Plasmo facilitates component modeling by means of modularization such that models can be constructed independently and connected to each other using linking constraints with a graph.    
It is also possible to model hierarchical systems (such as a network of networks) by linking nodes across different subgraphs within a larger graph.  
The graph-based modeling approach facilitates decomposition techniques such as graph partitioning and community detection approaches which can exploit parallel solvers such as [PIPS-NLP](https://github.com/Argonne-National-Laboratory/PIPS/tree/master/PIPS-NLP) and [DSP](https://github.com/Argonne-National-Laboratory/DSP).
Plasmo.jl been developed by the [Scalable Systems Laboratory](http://zavalab.engr.wisc.edu/) at the University of Wisconsin-Madison.

[![](https://img.shields.io/badge/docs-latest-blue.svg)](https://jalving.github.io/Plasmo.jl/dev/)

* Testing status:
    * TravisCI: [![Build Status](https://travis-ci.org/jalving/Plasmo.jl.svg?branch=master)](https://travis-ci.org/jalving/Plasmo.jl)
    * Coverage: [![codecov](https://codecov.io/gh/jalving/Plasmo.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/jalving/Plasmo.jl)

# Installation

```julia
Pkg.clone("https://github.com/jalving/Plasmo.jl")
```

# Simple Example

Plasmo.jl uses optimization models written with [JuMP](https://github.com/JuliaOpt/JuMP.jl).

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

## Acknowledgments
This code is based on work supported by the U.S. Department of Energy (DOE), Office of Science, under Contract No. DE-AC02-06CH11357 as well as the DOE Office of Electricity Delivery and Energy Reliability’s Advanced Grid Research and Development program at Argonne National Laboratory.

## Citing Plasmo
If you find Plasmo useful for your work, you might cite the current [pre-print](https://arxiv.org/pdf/1812.04983.pdf) of the manuscript:

    @article{JalvingZavala2018,
    archivePrefix = {arXiv},
    arxivId = {arXiv:1812.04983v1},
    author = {Jalving, Jordan and Cao, Yankai and Zavala, Victor M},
    eprint = {arXiv:1812.04983v1},
    title = {{Graph-Based Modeling and Simulation of Complex Systems}}
    }

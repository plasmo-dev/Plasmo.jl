![Plasmo logo](assets/plasmo.svg)

```@meta
CurrentModule = Plasmo
DocTestSetup = quote
    using Plasmo
end
```

# Plasmo.jl - Platform for Scalable Modeling and Optimization
Plasmo.jl is a graph-based optimization framework written in [Julia](https://julialang.org) that builds upon the [JuMP.jl](https://github.com/jump-dev/JuMP.jl) modeling language to offer a modular style to construct and solve optimization problems.
The package implements what is called an `OptiGraph` abstraction to create graph-structured optimization models and facilitate graph-based processing functions. An `OptiGraph` captures the underlying graph topology of an optimization problem using `OptiNodes` (which represent stand-alone self-contained optimization models) that are coupled by means of `OptiEdges` (which represent coupling constraints). The resulting topology can be used for tasks such as visualization, graph [partitioning](https://en.wikipedia.org/wiki/Graph_partition), and interfacing (and developing) decomposition-based solvers.

## Installation
Plasmo.jl works for Julia versions 1.6 and later. From Julia, Plasmo.jl can be installed using the `Pkg` module:

```julia
import Pkg
Pkg.add("Plasmo")
```
or alternatively from the Julia package manager by performing the following:
```
pkg> add Plasmo
```


## Contents

```@contents
Pages = [
    "documentation/quickstart.md"
    "documentation/modeling.md"
    "documentation/graph_processing.md"
    "documentation/api_docs.md"
    ]
Depth = 2
```

## Future Development
There are currently a few major development avenues for Plasmo.jl. Here is a list of some of the major features we intend to add for future releases:

* Distributed modeling capabilities
* Custom optigraph partitioning algorithms
* Decomposition-based solver development
* GraphOptInterface.jl development
* Interface with InfiniteOpt.jl

We are also looking for help from new contributors. If you would like to contribute to Plasmo.jl, please create a new issue or pull request on the [GitHub page](https://github.com/plasmo-dev/Plasmo.jl)

## Index

```@index
```

## Citing Plasmo.jl

If you find Plasmo.jl useful for your work, we ask that you cite the [manuscript](https://link.springer.com/article/10.1007/s12532-022-00223-3):
``` sourceCode
@article{Jalving2022,
  author = {Jalving, Jordan and Shin, Sungho and Zavala, Victor M.},
  title = {A graph-based modeling abstraction for optimization: concepts and implementation in {Plasmo.jl}},
  journal = {Mathematical Programming Computation},
  volume = {14},
  pages = {699--747},
  year = {2022},
  doi = {10.1007/s12532-022-00223-3}
}
```
You can access an earlier [pre-print](https://arxiv.org/abs/2006.05378) of this article.


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
doi = {10.1016/j.compchemeng.2019.03.009}
}
```
A pre-print of this paper can also be found [here](https://arxiv.org/abs/1812.04983)

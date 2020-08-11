![Plasmo logo](assets/plasmo.svg)

```@meta
CurrentModule = Plasmo
DocTestSetup = quote
    using Plasmo
    using GLPK
    using Plots
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

The below example demonstrates the construction of a simple nonlinear optimization problem that contains two `OptiNodes` coupled by a simple `LinkConstraint` (which creates an `OptiEdge`) and solved with
the linear optimization solver GLPK. More detailed examples can be found in the [examples folder](https://github.com/zavalab/Plasmo.jl/tree/master/examples).

Once Plasmo.jl has been installed, you can use it from a Julia session as following:
```jldoctest quickstart_example
julia> using Plasmo
```

For this example we also need to import the GLPK optimization solver and the Plots package which we use to visualize graph structure.
```julia
julia> using GLPK
julia> using Plots
```
!!! note
    We highlight that it is possible to use any solver that works with JuMP. By default, when using a standard optimization solver available through JuMP, Plasmo.jl will aggregate
    the `OptiGraph` into a single node to solve (hence ignoring the graph structure).  While it is useful having such granular control to build optimization models with an
    `OptiGraph`, we note that this aggregation step introduces additional model-building time when using standard optimization solvers (such as GLPK and Ipopt).

### Create an OptiGraph

The following command will create an `OptiGraph` model.  We also see the printed output which denotes the number of optinodes, linking constraints, and subgraphs within the `OptiGraph`.
```jldoctest quickstart_example
julia> graph = OptiGraph()
OptiGraph:
local nodes: 0, total nodes: 0
local link constraints: 0, total link constraints 0
local subgraphs: 0, total subgraphs 0
```

!!! note
    An `OptiGraph` distinguishes between local and total entities (i.e. nodes, edges, link constraints, and subgraphs). This distinction
    between local and total is used to describe hierarchical graph structures which are introduced in [Hierarchical Modeling](@ref).

### Add OptiNodes

```jldocest quickstart_example
julia> @optinode(graph,n1)
OptiNode w/ 0 Variable(s)

julia> @variable(n1, y >= 2)
y

julia> @variable(n1, x >= 0)
x

julia> @constraint(n1,x + y >= 3)
x + y >= 3

julia> @objective(n1, Min, y)
y
```

```@meta
DocTestSetup = nothing
```

```@meta
    DocTestSetup = quote
    using Plasmo
    using GLPK
    using Plots

    graph = OptiGraph()
    @optinode(graph,n1)
    @variable(n1, y >= 2)
    @variable(n1,x >= 0)
    @constraint(n1,x + y >= 3)
    @objective(n1, Min, y)

    @optinode(graph,n2);
    @variable(n2, y >= 0);
    @variable(n2, x >= 0);
    @constraint(n2,x + y >= 3);
    @objective(n2, Min, y);

    @optinode(graph,n3);
    @variable(n3, y >= 0);
    @variable(n3,x >= 0);
    @constraint(n3,x + y >= 3);
    @objective(n3, Min, y);  
end
```

```julia
julia> @optinode(graph,n2);
julia> @variable(n2, y >= 0);
julia> @variable(n2,x >= 0);
julia> @constraint(n2,x + y >= 3);
julia> @objective(n2, Min, y);

julia> @optinode(graph,n3);
julia> @variable(n3, y >= 0);
julia> @variable(n3,x >= 0);
julia> @constraint(n3,x + y >= 3);
julia> @objective(n3, Min, y);  
```

```jldoctest quickstart_example_2
julia> println(graph)
OptiGraph:
local nodes: 3, total nodes: 3
local link constraints: 0, total link constraints 0
local subgraphs: 0, total subgraphs 0
```

```@meta
DocTestSetup = nothing
```

### Create LinkConstraints (OptiEdges)

```jldoctest quickstart_example_2
julia> @linkconstraint(graph, n1[:x] + n2[:x] + n3[:x] == 3)
LinkConstraintRef(1, OptiEdge w/ 1 Constraint(s))

julia> println(graph)
OptiGraph:
local nodes: 3, total nodes: 3
local link constraints: 1, total link constraints 1
local subgraphs: 0, total subgraphs 0
```

### Solve and Query Solution
```jldoctest quickstart_example_2
julia> optimize!(graph,GLPK.Optimizer)
Converting OptiGraph to OptiNode...
Optimizing OptiNode
Found Solution
```
Now we can query the solution
```jldoctest quickstart_example_2
julia> value(n1,n1[:x])    
1.0

julia> value(n2,n2[:x])
2.0

julia> value(n3,n3[:x])
0.0

julia> objective_value(graph)
6.0
```      

### Visualize the Structure
```@setup plot_example
    using Plasmo
    using Plots

    graph = OptiGraph()
    @optinode(graph,n1)
    @variable(n1, y >= 2)
    @variable(n1,x >= 0)
    @constraint(n1,x + y >= 3)
    @objective(n1, Min, y)

    @optinode(graph,n2);
    @variable(n2, y >= 0);
    @variable(n2,x >= 0);
    @constraint(n2,x + y >= 3);
    @objective(n2, Min, y);

    @optinode(graph,n3);
    @variable(n3, y >= 0);
    @variable(n3, x >= 0);
    @constraint(n3,x + y >= 3);
    @objective(n3, Min, y);  

    @linkconstraint(graph, n1[:x] + n2[:x] + n3[:x] == 3);
```

Graph topology

```@repl plot_example
plt_graph = Plots.plot(graph,node_labels = true, markersize = 60,labelsize = 30, linewidth = 4,layout_options = Dict(:tol => 0.01,:iterations => 2));

Plots.savefig(plt_graph,"graph_layout.svg");
```
![](graph_layout.svg)

Graph adjacency
```@repl plot_example
plt_matrix = Plots.spy(graph1,node_labels = true,markersize = 30);   
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

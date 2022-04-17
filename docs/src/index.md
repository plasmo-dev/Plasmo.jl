![Plasmo logo](assets/plasmo.svg)

```@meta
CurrentModule = Plasmo
DocTestSetup = quote
    using Plasmo
    using GLPK
    using PlasmoPlots
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
pkg> ] add Plasmo
```

## Quickstart Example
This quickstart example gives a brief overview of the functions needed to effectively use Plasmo.jl to build optimization models. If you are familiar with [JuMP.jl](https://github.com/jump-dev/JuMP.jl),
much of the functionality you see here will be familiar. In fact, the primary `OptiGraph` and `OptiNode` objects from Plasmo.jl extend the `JuMP.AbstractModel` and support many JuMP functions.  

The below example demonstrates the construction of a simple linear optimization problem that contains two `OptiNodes` coupled by a simple `LinkConstraint` (which creates an `OptiEdge`) which is solved with
the GLPK linear optimization solver. More detailed examples can be found in the [examples folder](https://github.com/zavalab/Plasmo.jl/tree/master/examples).

Once Plasmo.jl has been installed, you can use it from a Julia session as following:
```jldoctest quickstart_example
julia> using Plasmo
```

For this example we also need to import the GLPK optimization solver and the [PlasmoPlots](https://github.com/zavalab/PlasmoPlots.jl) package which we use to visualize graph structure.
```julia
julia> using GLPK
julia> using PlasmoPlots
```

### Create an OptiGraph

The following command will create the `OptiGraph` referred to by `graph`. We also see the printed output which denotes the number of `OptiNodes`, `OptiEdges`, `LinkConstraints`, and subgraphs (other `OptiGraphs` contained within `graph`).
```jldoctest quickstart_example
julia> graph = OptiGraph()
OptiGraph:      # elements (including subgraphs)
-------------------------------------------------------------------
OptiNodes:           0              (0)
OptiEdges:           0              (0)
LinkConstraints:     0              (0)
sub-OptiGraphs:      0              (0)
```

!!! note
    An `OptiGraph` distinguishes between its direct elements (optinodes and optiedges contained directly within the graph) and its subgraph elements (optinodes and optiedges contained within its subgraphs). This distinction
    is used to describe hierarchical graph structures in [Hierarchical Modeling](@ref).

### Add OptiNodes
An `OptiGraph` consists of `OptiNodes` which contain stand-alone optimization models. An `OptiNode` supports JuMP
macros used to create variables, constraints, expressions, and objective functions (i.e. it supports JuMP macros such as `@variable`, `@constraint`, and `@objective`). The simplest way to add optinodes to an optigraph is
to use the `@optinode` macro as shown in the following code snippet. For this example we create the optinode `n1`, we create two variables `x` and `y`, and we add
a single constraint and an objective function.

```jldocest quickstart_example
julia> @optinode(graph, n1)
OptiNode w/ 0 Variable(s) and 0 Constraint(s)

julia> @variable(n1, y >= 2)
n1[:y]

julia> @variable(n1, x >= 0)
n1[:x]

julia> @constraint(n1, x + y >= 3)
n1[:y] + n1[:x] ≥ 3.0

julia> @objective(n1, Min, y)
n1[:y]
```

```@meta
DocTestSetup = nothing
```

```@meta
    DocTestSetup = quote
    using Plasmo
    using GLPK
    using PlasmoPlots

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

We can create more optinodes and add variables, constraints, and objective functions to each of them.
```julia
julia> @optinode(graph, n2);
julia> @variable(n2, y >= 0);
julia> @variable(n2, x >= 0);
julia> @constraint(n2, x + y >= 3);
julia> @objective(n2, Min, y);

julia> @optinode(graph, n3);
julia> @variable(n3, y >= 0);
julia> @variable(n3, x >= 0);
julia> @constraint(n3, x + y >= 3);
julia> @objective(n3, Min, y);  
```

```jldoctest quickstart_example_2
julia> println(graph)
OptiGraph: # elements (including subgraphs)
-------------------------------------------------------------------
      OptiNodes:     3              (0)
      OptiEdges:     0              (0)
LinkConstraints:     0              (0)
 sub-OptiGraphs:     0              (0)
```

```@meta
DocTestSetup = nothing
```

### Create LinkConstraints (and hence OptiEdges)
`LinkConstraints` can be used to couple variables between optinodes. Creating a link-constraint automatically creates an
`OptiEdge` in the optigraph which describes the connectivity between optinodes.  Link-constraints are created using the `@linkconstraint` macro which takes the exact same
input as the `JuMP.@constraint` macro. The following code creates a link-constraint between variables on the three optinodes.

```jldoctest quickstart_example_2
julia> @linkconstraint(graph, n1[:x] + n2[:x] + n3[:x] == 3);
: n1[:x] + n2[:x] + n3[:x] = 3.0

julia> println(graph)
OptiGraph: # elements (including subgraphs)
-------------------------------------------------------------------
      OptiNodes:     3              (3)
      OptiEdges:     1              (1)
LinkConstraints:     1              (1)
 sub-OptiGraphs:     0              (0)

```
!!! note
    Using the standard `@constraint` macro on an `OptiGraph` will also create a `LinkConstraint`. The `@linkconstraint` syntax is preferred to help model readability.

!!! note
    Nonlinear link-constraints are not yet supported.

### Solve the OptiGraph and Query the Solution

When using a [MathOptInterface.jl](https://github.com/jump-dev/MathOptInterface.jl) (MOI) optimization solver, we can optimize an `OptiGraph` using the `set_optimizer` and `optimize!` functions extended from JuMP.  
Plasmo.jl will translate the optigraph into an MOI optimizer to solve the model.
```jldoctest quickstart_example_2
julia> set_optimizer(graph,GLPK.Optimizer)
julia> optimize!(graph)
```

After returning from the optimizer we can query the termination status using `termination_status(graph::OptiGraph)` (again just like in JuMP). We can also
query the solution of variables using `value(var::VariableRef)` and the
objective value of the graph using `objective_value(graph::OptiGraph)`
```jldoctest quickstart_example_2
julia> termination_status(graph)   
MOI.OPTIMAL

julia> value(n1[:x])    
1.0

julia> value(n2[:x])
2.0

julia> value(n3[:x])
0.0

julia> objective_value(graph)
6.0
```     

!!! note
    It is also possible to optimize individual optinodes, or even optimize different optigraphs that share the same optinode . The latest optimization result is always accessible using
    `value(var::VariableRef)`. The results specific to an `OptiNode` or `OptiGraph` can be accessed with `value(node::OptiNode, var::JuMP.Variableref)` (for optinodes) or `value(graph::OptiGraph, var::JuMP.VariableRef)`
    (for optigraphs).

!!! note
    Plasmo.jl assumes the objective function of each optinode is added by default.  The objective function for an `OptiGraph` can be changed using the `@objective` macro
    on the `OptiGraph` itself. This will update the local objective function on each `OptiNode`.

### Visualize the Structure

```@setup plot_example
    using Plasmo
    using PlasmoPlots

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

Lastly, it is often useful to visualize the structure of an `OptiGraph`. The visualization can lead to insights about an optimization problem, but
it is also helpful just to see the connectivity. Plasmo.jl uses [PlasmoPlots](https://github.com/zavalab/PlasmoPlots.jl) which builds on [Plots.jl](https://github.com/JuliaPlots/Plots.jl) and [NetworkLayout.jl](https://github.com/JuliaGraphs/NetworkLayout.jl) to visualize the layout of an `OptiGraph`. The code here shows how to obtain the graph topology using `PlasmoPlots.graph_layout(graph::OptiGraph)` and we plot the underlying adjacency matrix structure using `PlasmoPlots.matrix_layout(graph::OptiGraph)` function. Both of these functions can accept keyword arguments to customize their layout or appearance.
The matrix visualization also encodes information on the number of variables and constraints in each optinode and optiedge. The left figure shows a standard graph visualization where we draw an edge between each pair of nodes
if they share an edge, and the right figure shows the matrix representation where labeled blocks correspond to nodes and blue marks represent linking constraints that connect their variables. The node layout helps visualize the overall connectivity of the graph while the matrix layout helps visualize the size of nodes and edges.


```@repl plot_example
plt_graph = PlasmoPlots.graph_layout(graph,node_labels = true, markersize = 30,labelsize = 15, linewidth = 4,layout_options = Dict(:tol => 0.01,:iterations => 2),plt_options = Dict(:legend => false,:framestyle => :box,:grid => false,:size => (400,400),:axis => nothing));

Plots.savefig(plt_graph,"graph_layout.svg");

plt_matrix = PlasmoPlots.matrix_layout(graph,node_labels = true,markersize = 15);   

Plots.savefig(plt_matrix,"matrix_layout.svg");
```
```@raw html
<img src="graph_layout.svg" alt="graph" width="400"/>
```
```@raw html
<img src="matrix_layout.svg" alt="matrix" width="400"/>
```

## Contents

```@contents
Pages = [
    "documentation/modeling.md"
    "documentation/partitioning.md"
    "documentation/solvers.md"
    "documentation/api_docs.md"
    ]
Depth = 2
```

## Future Development
There are currently a few major development avenues for Plasmo.jl. Here is a list of some of the major features we intend to add for future releases:

* Parallel & Distributed modeling capabilities
* Nonlinear linking constraints
* Graph metrics and custom partitioning algorithms
* Better distributed solver support

We are also looking for help from new contributors. If you would like to contribute to Plasmo.jl, please create a new issue or pull request on the [GitHub page](https://github.com/zavalab/Plasmo.jl)

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

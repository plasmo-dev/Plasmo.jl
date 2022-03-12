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
The package implements what is called an `OptiGraph` abstraction to create graph-structured optimization models and works at a high level of abstraction to facilitate graph-based processing tasks. An `OptiGraph` captures the underlying graph topology of an optimization problem using `OptiNodes` (which represent stand-alone self-contained optimization models) that are coupled by means of `OptiEdges` (which represent coupling constraints). The resulting topology facilitates various graph processing tasks such as visualization, graph [partitioning](https://en.wikipedia.org/wiki/Graph_partition), and interfacing (and developing) decomposition-based solvers.

## Installation
Plasmo.jl works for Julia versions 1.0 and later. From Julia, Plasmo.jl can be installed using the `Pkg` module:

```julia
import Pkg
Pkg.add("Plasmo")
```
or alternatively from the Julia package manager by performing the following:
```
pkg> ] add Plasmo
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

For this example we also need to import the GLPK optimization solver and the PlasmoPlots package which we use to visualize graph structure.
```julia
julia> using GLPK
julia> using PlasmoPlots
```

### Create an OptiGraph

The following command will create an `OptiGraph` model.  We also see the printed output which denotes the number of optinodes, linking constraints, and subgraphs within the `OptiGraph`.
```jldoctest quickstart_example
julia> graph = OptiGraph()
OptiGraph:       # of elements,(including subgraphs)
OptiNodes:       0,(0)
OptiEdges:       0,(0)
LinkConstraints: 0,(0)
sub-OptiGraphs:  0,(0)
```

!!! note
    An `OptiGraph` distinguishes between its direct elements (e.g. optinodes and optiedges contained with the graph) and its subgraph elements (e.g. optinodes and optiedges contained within its subgraphs). This distinction
    is used to describe hierarchical graph structures in [Hierarchical Modeling](@ref).

### Add OptiNodes
An `OptiGraph` consists of `OptiNodes` which contain stand-alone optimization models. An `OptiNode` extends a `JuMP.AbstractModel` (and also a wraps a `JuMP.Model`) and supports the same
macros to create variables, constraints, expressions, and add objective functions (i.e. it supports macros like `@variable`, `@constraint`, and `@objective`).  The simplest way to add optinodes to an optigraph is
to use the `@optinode` macro as shown in the following code snippet. For this example, we create the `OptiNode` `n1`, we create two variables `x` and `y`, and add
a single constraint and an objective function.

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

We can create more `OptiNodes` and add variables, constraints, and objective functions to each node in the graph.
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
OptiGraph:       # of elements,(including subgraphs)
OptiNodes:       3,(3)
OptiEdges:       0,(0)
LinkConstraints: 0,(0)
sub-OptiGraphs:  0,(0)
```

```@meta
DocTestSetup = nothing
```

### Create LinkConstraints (and hence OptiEdges)
Linking constraints can be used to couple variables between optinodes.  Beneath the modeling surface, creating a linking constraint induces an
`OptiEdge` in the `OptiGraph` which describes its connectivity.  Linking constraints are created using the `@linkconstraint` macro which takes the exact same
input as the `JuMP.@constraint` macro.  The following code creates a linking constraint between variables on the three optinodes.

```jldoctest quickstart_example_2
julia> @linkconstraint(graph, n1[:x] + n2[:x] + n3[:x] == 3)
LinkConstraintRef(1, OptiEdge w/ 1 Constraint(s))

julia> println(graph)
OptiGraph:       # of elements,(including subgraphs)
OptiNodes:       3,(3)
OptiEdges:       1,(1)
LinkConstraints: 1,(1)
sub-OptiGraphs:  0,(0)
```

!!! note
    Nonlinear linking constraints are not yet supported. They will likely wait until the next `JuMP` NLP re-write.

### Solve and Query Solution

When using a `JuMP`/`MathOptInterface` enabled optimization solver, we can optimize an `OptiGraph` using the `optimize!` function (extended from JuMP).  
Plasmo.jl will translate the `OptiNode`s and `OptiEdge`s into a `MathOptInterface` backend and solve the model.
```jldoctest quickstart_example_2
julia> optimize!(graph,GLPK.Optimizer)
```

After finding a solution, we can query it using `value(::OptiNode,::VariableRef)` (just like in JuMP).   We can also query the
objective value of the graph using `objective_value(::OptiGraph)`
```jldoctest quickstart_example_2
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

Lastly, it is often useful to visualize the structure of an `OptiGraph`.  The visualization can lead to physical insights about an optimization problem (such as space-time dependencies), but
it is also helpful just to see the connectivity of the problem.  Plasmo.jl uses [PlasmoPlots](https://github.com/zavalab/PlasmoPlots.jl) which further uses [Plots.jl](https://github.com/JuliaPlots/Plots.jl) and [NetworkLayout.jl](https://github.com/JuliaGraphs/NetworkLayout.jl) to visualize the layout of an `OptiGraph`.  The code here shows how to obtain the graph topology using `PlasmoPlots.graph_layout(::OptiGraph)`
and we plot the underlying adjacency matrix structure using `PlasmoPlots.matrix_layout` function. Both of these functions can accept keyword arguments to customize their layout or appearance.
The matrix visualization also encodes information on the number of variables and constraints in each node and edge. The left figure shows a standard graph visualization where we draw an edge between each pair of nodes
if they share an edge, and the rightfigure shows the matrix representation where labeled blocks correspond to nodes and blue marks represent linking constraints that connect their variables. The node layout helps visualize the overall connectivity of the graph while the matrix layout helps visualize the size of nodes and edges.


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
    "documentation/plotting.md"
    ]
Depth = 2
```

## Future Development
There are currently a few major development avenues for `Plasmo.jl`. Here is a list of some of the major features we intend to add for future releases:

* Parallel modeling capabilities
* Nonlinear linking constraints
* Graph metrics and custom partitioning algorithms
* More distributed solver support


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

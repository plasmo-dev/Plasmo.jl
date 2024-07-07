# Quickstart

This quickstart gives a brief overview of the functions needed to effectively use Plasmo.jl to build optimization models. If you have used [JuMP.jl](https://github.com/jump-dev/JuMP.jl),
much of the functionality here will look familiar. In fact, the primary modeling objects in Plasmo.jl extend the `JuMP.AbstractModel` and support most JuMP methods.  

The below example demonstrates the construction of a simple linear optimization problem that contains two optinodes coupled by a simple linking contraint (which induces an [`OptiEdge`](@ref)) that is solved with
the [HiGHS](https://github.com/jump-dev/HiGHS.jl) linear optimization solver.

Once Plasmo.jl has been installed, you can use it from a Julia session as following:
```jldoctest quickstart
julia> using Plasmo
```

For this example we also need to import the HiGHS optimization solver and the [PlasmoPlots](https://github.com/plasmo-dev/PlasmoPlots.jl) package which we use to visualize the graph structure.
```jldoctest quickstart
julia> using HiGHS
```

## Create an OptiGraph

The following command will create the optigraph (referred to as `graph`). We also see the printed output which denotes the number of optinodes, optiedges, subgraphs, variables, and constraints in the graph.
```jldoctest quickstart
julia> graph = OptiGraph(;name=:quickstart_graph)
An OptiGraph
quickstart_graph #local elements  #total elements
--------------------------------------------------
          Nodes:         0                0
          Edges:         0                0
      Subgraphs:         0                0
      Variables:         0                0
    Constraints:         0                0

```

!!! note
    An [`OptiGraph`](@ref) distinguishes between its local elements (optinodes and optiedges contained directly within the graph) and its total elements (local elements plus elements contained within subgraphs). This distinction helps to describe nested graph structures in [Modeling with Subgraphs]().

## Add Variables and Constraints using OptiNodes
An optigraph consists of [`OptiNode`](@ref) objects which represent stand-alone optimization models. An optinode supports JuMP
macros used to create variables, constraints, expressions, and objective functions (i.e. it supports JuMP macros such as `@variable`, `@constraint`, `@expression` and `@objective`). The simplest way to add optinodes to an optigraph is
to use the [`@optinode`](@ref) macro as shown in the following code snippet. Here we create the optinode `n1` and add two variables `x` and `y`. We also add
a single constraint and an objective function to the node. By default, the name of a node is pre-pended with the name of the graph it was created in.

```jldoctest quickstart
julia> @optinode(graph, n1)
n1

julia> @variable(n1, y >= 2)
n1.y

julia> @variable(n1, x >= 1)
n1.x

julia> @constraint(n1, x + y >= 3)
n1.y + n1.x ≥ 3

julia> @objective(n1, Min, y)
n1.y

julia> graph
An OptiGraph
quickstart_graph #local elements  #total elements
--------------------------------------------------
          Nodes:         1                1
          Edges:         0                0
      Subgraphs:         0                0
      Variables:         2                2
    Constraints:         3                3

```


We can create more optinodes and add variables, constraints, and objective functions to each of them.

```jldoctest quickstart
@optinode(graph, n2);
@variable(n2, y >= 0);
@variable(n2, x >= 2);
@constraint(n2, x + y >= 3);
@objective(n2, Min, y);

@optinode(graph, n3);
@variable(n3, y >= 0);
@variable(n3, x >= 0);
@constraint(n3, x + y >= 3);
@objective(n3, Min, y);

println(graph)

# output

An OptiGraph
quickstart_graph #local elements  #total elements
--------------------------------------------------
          Nodes:         3                3
          Edges:         0                0
      Subgraphs:         0                0
      Variables:         6                6
    Constraints:         9                9

```


## Add Linking Constraints
A linking constraint can be created by adding a constraint to an [`OptiEdge`](@ref). Linking constraints 
couple variables across nodes (or graphs!) and can take any valid JuMP expression composed of node variables. We add a simple linear equality constraint
here between variables that exist on nodes `n1`, `n2`, and `n3`.

```jldoctest quickstart
julia> edge = add_edge(graph, n1, n2, n3);

julia> @constraint(edge, n1[:x] + n2[:x] + n3[:x] == 3)
n1.x + n2.x + n3.x = 3

julia> println(graph)
An OptiGraph
quickstart_graph #local elements  #total elements
--------------------------------------------------
          Nodes:         3                3
          Edges:         1                1
      Subgraphs:         0                0
      Variables:         6                6
    Constraints:        10               10

```

!!! note
    You can also create edges implicitly using the [`@linkconstraint`](@ref) macro which takes the exact same input as the `JuMP.@constraint` macro above. 
    The above snippet would correspond to doing:
    ```julia
    @linkconstraint(graph, n1[:x] + n2[:x] + n3[:x] == 3)
    ```
    This would create a new edge between nodes `n1`, `n2`, and `n3` (if one does not exist) and add the constraint to it. You can also use the `JuMP.@constraint` macro directly on an optigraph to generate linking constraints, but the syntax displayed here is preferred to help code readability.


## Solve the OptiGraph and Query the Solution

We can set the objective function of an optigraph using either the node objectives or by defining an objective directly using the `JuMP.@objective` macro on the graph. Since we already defined an 
objective for each node we can use the `set_to_node_objectives` function to denote the graph objective.
```jldoctest quickstart
julia> set_to_node_objectives(graph)

julia> objective_function(graph)
n1.y + n2.y + n3.y
```

!!! note
    The graph objective approach would look like:
    ```julia
    @objective(graph, Min, n1[:y] + n2[:y] + n3[:y])
    ```

Plasmo.jl uses [MathOptInterface.jl](https://github.com/jump-dev/MathOptInterface.jl) internally to interface with optimization solvers. 
We can optimize an optigraph using the [`set_optimizer`](@ref) and [`optimize!`](@ref) functions just like in JuMP.jl. Here we also set the HiGHS attribute `log_to_console` to false to 
suppress the output.
```jldoctest quickstart
julia> set_optimizer(graph, HiGHS.Optimizer);

julia> set_optimizer_attribute(graph, MOI.RawOptimizerAttribute("log_to_console"), false)

julia> optimize!(graph)

```


After returning from the optimizer we can query the termination status using [`termination_status`](@ref). We can also
query the solution of variables using [`value`](@ref) and the objective value of the graph using [`objective_value`](@ref)
```jldoctest quickstart
julia> termination_status(graph)   
OPTIMAL::TerminationStatusCode = 1

julia> value(graph, n1[:x])    
1.0

julia> value(graph, n2[:x])
2.0

julia> value(graph, n3[:x])
0.0

julia> objective_value(graph)
6.0

```     

!!! info
    It is possible to optimize individual optinodes or different optigraphs that contain the same optinode (nodes can be used in multiple optigraphs). Graph-specific solutions can be accessed using `value(node, variable)` (if optimizing a single node) or `value(graph, variable)` (if optimizing an optigraph). \\
    Note that optimizing a node creates a new graph internally; *the optimizer interface always goes through a graph*. It is also possible to use `value(variable)` without specifying a graph, but this will always return the value corresponding to the graph that created the node (this graph can be queried using `source_graph(node)`). Using `value(node`) is likely fine for most use-cases, but be aware that you should use the `value(graph, variable)` method when dealing with multiple graphs to avoid grabbing a wrong solution.

## Visualize the Structure

Lastly, it is often useful to visualize the structure of an optigraph. The visualization can lead to insights about an optimization problem and understand its connectivity. Plasmo.jl uses [PlasmoPlots.jl](https://github.com/plasmo-dev/PlasmoPlots.jl) (which builds on [Plots.jl](https://github.com/JuliaPlots/Plots.jl) and [NetworkLayout.jl](https://github.com/JuliaGraphs/NetworkLayout.jl)) to visualize the layout of an optigraph. The code here shows how to obtain the graph topology using [`PlasmoPlots.layout_plot`]() and we plot the corresponding incidence matrix structure using [`PlasmoPlots.matrix_plot`](). Both of these functions can accept keyword arguments to customize their layout or appearance.
The matrix visualization also encodes information on the number of variables and constraints in each optinode and optiedge. The left figure shows a standard graph visualization where we draw an edge between each pair of nodes
if they share an edge, and the right figure shows the matrix representation where labeled blocks correspond to nodes and blue marks represent linking constraints that connect their variables. The node layout helps visualize the overall connectivity of the graph while the matrix layout helps visualize the size of nodes and edges.

```julia
plt_graph = PlasmoPlots.layout_plot(
                graph,
                node_labels=true, 
                markersize=30, 
                labelsize=15, 
                linewidth=4,
                layout_options=Dict(
                    :tol=>0.01, 
                    :iterations=>2
                ),
                plt_options=Dict(
                    :legend=>false, 
                    :framestyle=>:box, 
                    :grid=>false,
                    :size=>(400,400), 
                    :axis=>nothing)
                )

plt_matrix = PlasmoPlots.matrix_plot(graph, node_labels=true, markersize=15)   
```

![graph_quickstart](../assets/graph_layout.svg) ![matrix_quickstart](../assets/matrix_layout.svg)

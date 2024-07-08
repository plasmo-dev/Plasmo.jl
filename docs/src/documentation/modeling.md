# Modeling with OptiGraphs
The primary data structure in Plasmo.jl is the [`OptiGraph`](@ref), a mathematical model composed of [`OptiNode`](@ref)s (which represent self-contained optimization problems) 
that are connected by [`OptiEdge`](@ref)s (which encapsulate linking constraints that couple optinodes). The optigraph is meant to offer a modular mechanism to create optimization problems and provide
methods that can help develop specialized solution strategies, visualize problem structure, or perform graph processing tasks such as partitioning.

The optigraph ultimately describes the following mathematical representation of an optimization problem:
```math
\begin{aligned}
    \min_{{\{x_n}\}_{n \in \mathcal{N}(\mathcal{G})}} & \quad \sum_{n \in \mathcal{N(\mathcal{G})}} f_n(x_n) \quad & (\textrm{Objective}) \\
    \textrm{s.t.} & \quad x_n \in \mathcal{X}_n,      \quad n \in \mathcal{N(\mathcal{G})}, \quad & (\textrm{Node Constraints})\\
    & \quad g_e(\{x_n\}_{n \in \mathcal{N}(e)}) = 0,  \quad e \in \mathcal{E(\mathcal{G})}. &(\textrm{Edge (Link) Constraints})
\end{aligned}
```
In this formulation, ``\mathcal{G}`` represents the optigraph, ``{\{x_n}\}_{n \in \mathcal{N}(\mathcal{G})}`` describes a collection of decision
variables over the set of nodes (optinodes) ``\mathcal{N}(\mathcal{G})``, and ``x_n`` is the set of
decision variables on node ``n``. The objective function for the optigraph ``\mathcal{G}`` is given by a composition of objective functions defined over optinodes ``f_n(x_n)``.
The second equation represents constraints on each optinode ``\mathcal{N}(\mathcal{G})``, and the third equation represents the collection of
linking constraints associated with optiedges ``\mathcal{E}(\mathcal{G})``. The constraints of an optinode ``n`` are represented by the set ``\mathcal{X}_n`` while the linking constraints
that correspond to an edge ``e`` are represented by the vector function ``g_e(\{x_n\}_{n \in \mathcal{N}(e)})``.

From an implementation standpoint, an optigraph extends much of the modeling functionality and syntax from [JuMP](https://github.com/jump-dev/JuMP.jl). 
We also sometimes drop the 'opti' prefix and refer to objects as graphs, nodes, and edges throughout the documentation, but we note when the 'opti' distincition is important.

!!! info

     The [`OptiNode`](@ref) and [`OptiGraph`](@ref) each extend a `JuMP.AbstractModel` and support JuMP macros such as 
     `@variable`, `@constraint`, `@expression`, and `@objective` as well as many other JuMP methods that work on a `JuMP.Model`. 
     The [`OptiEdge`](@ref) supports most JuMP methods as well but does not support `@variable` or `@objective`.

## Creating a New OptiGraph
An optigraph does not require any arguments to construct but it is recommended to include the optional `name` argument for tracking and model management purposes.
We begin by creating a new optigraph named `graph1`.


```jldoctest modeling
julia> using Plasmo

julia> graph1 = OptiGraph(;name=:graph1)
An OptiGraph
          graph1 #local elements  #total elements
--------------------------------------------------
          Nodes:         0                0
          Edges:         0                0
      Subgraphs:         0                0
      Variables:         0                0
    Constraints:         0                0
```

## Add Variables and Constraints using OptiNodes
Optinodes contain modular groups of optimization variables, constraints, and other model data.
The typical way to add optinodes to an graph is by using the [`@optinode`](@ref) macro where the below snippet adds the node `n1` to
`graph1`. 

```jldoctest modeling
julia> @optinode(graph1, n1)
n1
```

!!! note

    You can also use the [`add_node`](@ref) method to add individual optinodes. In this case, the above snippet would look like:
    n1 = add_node(graph1)

The [`@optinode`](@ref) macro is more useful for creating containers of optinodes like shown in the below code snippet.
Here, we create two more optinodes referred to as `nodes1`. This macro returns a `JuMP.DenseAxisArray` which
allows us to refer to each optinode using the produced index sets. For example, `nodes1[2]` and `nodes1[3]` each return the corresponding
optinode.

```jldoctest modeling
julia> @optinode(graph1, nodes1[2:3])
1-dimensional DenseAxisArray{OptiNode{OptiGraph},1,...} with index sets:
    Dimension 1, 2:3
And data, a 2-element Vector{OptiNode{OptiGraph}}:
 nodes1[2]
 nodes1[3]

julia> nodes1[2]
nodes1[2]

julia> nodes1[3]
nodes1[3]
```

Each optinode supports adding variables, constraints, expressions, and an objective function. 
Here we loop through each optinode in `graph1` using the [`local_nodes`](@ref) function and we construct underlying model elements.

```jldoctest modeling
julia>  for node in all_nodes(graph1)
            @variable(node,x >= 0)
            @variable(node, y >= 2)
            @constraint(node, node_constraint_1, x + y >= 3)
            @constraint(node, node_constraint_2, x^3 >= 1)
            @objective(node, Min, x + y)
        end

julia> graph1
An OptiGraph
          graph1 #local elements  #total elements
--------------------------------------------------
          Nodes:         3                3
          Edges:         0                0
      Subgraphs:         0                0
      Variables:         6                6
    Constraints:        12               12

```

Variables within an optinode can be accessed directly by indexing the associated symbol. This enclosed name-space is useful for
referencing variables on different optinodes when creating linking constraints or optigraph objective functions.
```jldoctest modeling
julia> n1[:x]
n1[:x]

julia> nodes1[2][:x]
nodes1[2][:x]
```

## Add Linking Constraints using Edges
An [OptiEdge](@ref) can be used to store linking constraints that couple variables across optinodes. The simplest way to create a linking constraint is to use the [`@linkconstraint`](@ref) macro which accepts the same input as the `JuMP.@constraint` macro, but it requires an expression with at least two variables that exists on two different optinodes. The actual constraint is stored on the edge that connects the optinodes referred to in 
the linking constraint. This optiedge is created if it does not already exist.

```jldoctest modeling
julia> @linkconstraint(graph1, link_reference, n1[:x] + nodes1[2][:x] + nodes1[3][:x] == 3)
n1[:x] + nodes1[2][:x] + nodes1[3][:x] = 3

```

!!! note

    Some users may choose to create the edge manually and add the constraint like following:
    ```julia
    edge = add_edge(graph1, n1, nodes1[2], nodes1[3])
    @constraint(edge, n1[:x] + nodes1[2][:x] + nodes1[3][:x] == 3)
    ```
    Both approaches are equivalent.


## Add an Objective Function
By default, the graph objective is empty even if objective functions exist on nodes. We leave it up to the user to determine what the objective function for the graph should be 
given its contained nodes. We provide the convenience function [`set_to_node_objectives`](@ref) which will set the graph objective function to the sum of all the node objectives. 
We can set the graph objective like following:

```jldoctest modeling
julia> set_to_node_objectives(graph1)

julia> objective_function(graph1)
n1[:x] + n1[:y] + nodes1[2][:x] + nodes1[2][:y] + nodes1[3][:x] + nodes1[3][:y]

``` 

## Solving and Querying Solutions

An optimizer can be specified using the [`set_optimizer`](@ref) function which supports any [MathOptInterface.jl](https://github.com/jump-dev/MathOptInterface.jl) optimizer. 
For example, we use the `Ipopt.Optimizer` from the [Ipopt.jl](https://github.com/jump-dev/Ipopt.jl) to solve the optigraph like following:

```jldoctest modeling
julia> using Ipopt

julia> using Suppressor # suppress complete output

julia> set_optimizer(graph1, Ipopt.Optimizer);

julia> set_optimizer_attribute(graph1, "print_level", 0); #suppress Ipopt output

julia> @suppress optimize!(graph1)

```

The solution of an optigraph is stored directly on its optinodes and optiedges. Variables values, constraint duals, objective function values, and solution status codes can be queried just like in JuMP.

```jldoctest modeling
julia> termination_status(graph1)   
LOCALLY_SOLVED::TerminationStatusCode = 4

julia> value(n1[:x])    
1.0

julia> value(nodes1[2][:x])
1.0

julia> value(nodes1[3][:x])
1.0

julia> round(objective_value(graph1))
9.0

julia> round(dual(link_reference), digits = 2)
-0.25

julia> round(dual(n1[:node_constraint_1]), digits = 2)
0.5

julia> round(dual(n1[:node_constraint_2]), digits = 2)
0.25
```   

## Plotting OptiGraphs
We can also plot the structure of `graph1` using both graph and matrix layouts from the [PlasmoPlots](https://github.com/plasmo-dev/PlasmoPlots.jl) package.

```julia
using PlasmoPlots

plt_graph = layout_plot(
    graph1,
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
        :axis => nothing
    )
);

plt_matrix = matrix_layout(graph1, node_labels=true, markersize=15);   
```

![graph_modeling1](../assets/graph1_layout.svg) ![matrix_modeling1](../assets/matrix1_layout.svg)

!!! info

    The `layout_plot` and `matrix_plot` functions both return a `Plots.plot` object which can be used for further customization and saving using `Plots.jl`

## Modeling with Subgraphs
A fundamental feature of modeling with optigraphs is the ability to create nested optimization structures using subgraphs (i.e. sub-optigraphs). 
Subgraphs are created using the [`add_subgraph`](@ref) method which embeds an optigraph as a subgraph within a higher level optigraph. 
This is demonstrated in the below snippets. First, we create two new optigraphs in the same fashion as above.

```jldoctest modeling
# create graph2
graph2 = OptiGraph(;name=:graph2);
@optinode(graph2, nodes2[1:3]);
for node in all_nodes(graph2)
    @variable(node, x >= 0)
    @variable(node, y >= 2)
    @constraint(node,x + y >= 5)
    @objective(node, Min, y)
end
@linkconstraint(graph2, nodes2[1][:x] + nodes2[2][:x] + nodes2[3][:x] == 5);

# create graph3
graph3 = OptiGraph(;name=:graph3);
@optinode(graph3, nodes3[1:3]);
for node in all_nodes(graph3)
    @variable(node, x >= 0)
    @variable(node, y >= 2)
    @constraint(node,x + y >= 5)
    @objective(node, Min, y)
end
@linkconstraint(graph3, nodes3[1][:x] + nodes3[2][:x] + nodes3[3][:x] == 7);

graph3

# output

An OptiGraph
          graph3 #local elements  #total elements
--------------------------------------------------
          Nodes:         3                3
          Edges:         1                1
      Subgraphs:         0                0
      Variables:         6                6
    Constraints:        10               10

```

We now have three optigraphs (`graph1`,`graph2`, and `graph3`), each with their own local optinodes and optiedges.  
These three optigraphs can be embedded into a higher level optigraph using the following snippet:

```jldoctest modeling
julia> graph0 = OptiGraph(;name=:root_graph)
An OptiGraph
      root_graph #local elements  #total elements
--------------------------------------------------
          Nodes:         0                0
          Edges:         0                0
      Subgraphs:         0                0
      Variables:         0                0
    Constraints:         0                0


julia> add_subgraph(graph0, graph1);

julia> graph0
An OptiGraph
      root_graph #local elements  #total elements
--------------------------------------------------
          Nodes:         0                3
          Edges:         0                1
      Subgraphs:         1                1
      Variables:         0                6
    Constraints:         0               13

julia> add_subgraph(graph0, graph2);

julia> graph0
An OptiGraph
      root_graph #local elements  #total elements
--------------------------------------------------
          Nodes:         0                6
          Edges:         0                2
      Subgraphs:         2                2
      Variables:         0               12
    Constraints:         0               23


julia> add_subgraph(graph0, graph3);

julia> graph0
An OptiGraph
      root_graph #local elements  #total elements
--------------------------------------------------
          Nodes:         0                9
          Edges:         0                3
      Subgraphs:         3                3
      Variables:         0               18
    Constraints:         0               33

```
Here, we see the distinction between local and total graph elements. After we add all three subgraphs
to `graph0`, we see that it contains 0 local optinodes, but contains 9 total optinodes which are elements of its subgraphs. This hierarchical distinction is also
made for optiedges and nested subgraphs.

Using this nested approach, linking constraints can be expressed both locally and globally. For instance, we can add a linking constraint to `graph0` that
connects optinodes across its subgraphs like following:
```jldoctest modeling
julia> @linkconstraint(graph0, nodes1[3][:x] + nodes2[2][:x] + nodes3[1][:x] == 10)
nodes1[3][:x] + nodes2[2][:x] + nodes3[1][:x] = 10

julia> graph0
An OptiGraph
      root_graph #local elements  #total elements
--------------------------------------------------
          Nodes:         0                9
          Edges:         1                4
      Subgraphs:         3                3
      Variables:         0               18
    Constraints:         1               34

```
`graph0` now contains 1 local edge, and 4 total edges (3 from the subgraphs). The higher level edge linking constraint 
can be thought of as a global constraint that connects subgraphs. This hierarchical construction can be useful for developing optimization problems
separately and then coupling them in a higher level optigraph.

We can lastly plot the hierarchical optigraph and see the nested subgraph structure.

```julia
using PlasmoPlots

plt_graph0 = PlasmoPlots.layoutplot(
    graph0,
    node_labels=true,
    markersize=60,
    labelsize=30,
    linewidth=4,
    subgraph_colors=true,
    layout_options = Dict(
        :tol=>0.001,
        :C=>2,
        :K=>4,
        :iterations=>5
    )
)

plt_matrix0 = PlasmoPlots.matrix_plot(
    graph0,
    node_labels = true,
    subgraph_colors = true,
    markersize = 16
)
```

![graph_modeling2](../assets/graph0_layout.svg) ![matrix_modeling2](../assets/matrix0_layout.svg)


## Query OptiGraph Attributes
Plasmo.jl offers various methods to inspect the optigraph data structures (see the [API Documentation](@ref) for a full list). We can use [`local_nodes`](@ref) to retrieve an array of
the optinodes contained directly within an optigraph, or we can use [`all_nodes`](@ref) to recursively retrieve all of the optinodes in an optigraph (which includes the nodes in its subgraphs).

```jldoctest modeling
julia> local_nodes(graph1)
3-element Vector{OptiNode{OptiGraph}}:
 n1
 nodes1[2]
 nodes1[3]

julia> local_nodes(graph0)
OptiNode{OptiGraph}[]

julia> all_nodes(graph0)
9-element Vector{OptiNode{OptiGraph}}:
 n1
 nodes1[2]
 nodes1[3]
 nodes2[1]
 nodes2[2]
 nodes2[3]
 nodes3[1]
 nodes3[2]
 nodes3[3]

```

It is also possible to query for optiedges in the same way using [`local_edges`](@ref) and [`all_edges`](@ref).
```jldoctest modeling
julia> local_edges(graph1)
1-element Vector{OptiEdge{OptiGraph}}:
 graph1.e1

julia> local_edges(graph0)
1-element Vector{OptiEdge{OptiGraph}}:
 root_graph.e1

julia> all_edges(graph0)
4-element Vector{OptiEdge{OptiGraph}}:
 root_graph.e1
 graph1.e1
 graph2.e1
 graph3.e1

```

We can query linking constraints using [`local_link_constraints`](@ref) and [`all_link_constraints`](@ref).

```jldoctest modeling
julia> local_link_constraints(graph1)
1-element Vector{ConstraintRef}:
 n1[:x] + nodes1[2][:x] + nodes1[3][:x] = 3

julia> local_link_constraints(graph0)
1-element Vector{ConstraintRef}:
 nodes1[3][:x] + nodes2[2][:x] + nodes3[1][:x] = 10

julia> all_link_constraints(graph0)
4-element Vector{ConstraintRef}:
 nodes1[3][:x] + nodes2[2][:x] + nodes3[1][:x] = 10
 n1[:x] + nodes1[2][:x] + nodes1[3][:x] = 3
 nodes2[1][:x] + nodes2[2][:x] + nodes2[3][:x] = 5
 nodes3[1][:x] + nodes3[2][:x] + nodes3[3][:x] = 7
```

We can lastly query subgraphs using [`local_subgraphs`](@ref) and [`all_subgraphs`](@ref) methods.

```jldoctest modeling
julia> local_subgraphs(graph0)
3-element Vector{OptiGraph}:
 An OptiGraph
          graph1 #local elements  #total elements
--------------------------------------------------
          Nodes:         3                3
          Edges:         1                1
      Subgraphs:         0                0
      Variables:         6                6
    Constraints:        13               13

 An OptiGraph
          graph2 #local elements  #total elements
--------------------------------------------------
          Nodes:         3                3
          Edges:         1                1
      Subgraphs:         0                0
      Variables:         6                6
    Constraints:        10               10

 An OptiGraph
          graph3 #local elements  #total elements
--------------------------------------------------
          Nodes:         3                3
          Edges:         1                1
      Subgraphs:         0                0
      Variables:         6                6
    Constraints:        10               10

```

## Managing Solutions with OptiGraphs

While it is common to use an optigraph as a means to build a singular optimization problem that can be solved with standard solvers, it is also possible
to come up with custom solution strategies that consist of solving smaller subgraphs or use optigraph elements to generate new 
optigraphs we can solve. To demonstrate, assume we first want to solve each subgraph in `graph0` in isolation. This can be done like following:

```jldoctest modeling
# optimize each subgraph with Ipopt
for subgraph in local_subgraphs(graph0)
    @objective(subgraph, Min, sum(all_variables(subgraph)))
    set_optimizer(subgraph, Ipopt.Optimizer)
    set_optimizer_attribute(subgraph, "print_level", 0);
    optimize!(subgraph)
end

# check termination status of each solve
termination_status.(local_subgraphs(graph0))

# output

3-element Vector{MathOptInterface.TerminationStatusCode}:
 LOCALLY_SOLVED::TerminationStatusCode = 4
 LOCALLY_SOLVED::TerminationStatusCode = 4
 LOCALLY_SOLVED::TerminationStatusCode = 4
```

We can query the value of each solution using [`value`](@ref) like before, but lets instead specify the graph argument for clarity.

```jldoctest modeling
julia> value(graph1, n1[:x])
1.0

julia> n2 = graph2[1] # get first node on graph2
nodes2[1]

julia> round(value(graph2, n2[:x]); digits=2)
1.67

julia> n3 = graph3[1] # get first node on graph3
nodes3[1]

julia> round(value(graph3, n3[:x]); digits=2)
2.33
```

Now assume we want to use these subgraph solutions to initialize the full graph solution. We could do this using [`JuMP.set_start_value`](@ref) like following:

```jldoctest modeling
julia> set_start_value.(all_variables(graph1), value.(graph1, all_variables(graph1)));

julia> set_start_value.(all_variables(graph2), value.(graph2, all_variables(graph2)));

julia> set_start_value.(all_variables(graph3), value.(graph3, all_variables(graph3)));
```

Now that each subgraph has a new initial solution, the total initial solution can be used to optimize `graph0` since all of the subgraph attributes will be copied over.

```jldoctest modeling
julia> @objective(graph0, Min, sum(all_variables(graph0))); # set graph0 objective

julia> set_optimizer(graph0, Ipopt.Optimizer);

julia> set_optimizer_attribute(graph0, "print_level", 0);

julia> optimize!(graph0);

julia> termination_status(graph0)
LOCALLY_SOLVED::TerminationStatusCode = 4

```

While somewhat simple, this example shows what kinds of model approaches can be taken with Plasmo.jl. Checkout [Graph Processing and Analysis](@ref) for more advanced functionality 
that makes use of the optigraph structure to define and solve problems.
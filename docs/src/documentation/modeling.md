# Modeling with OptiGraphs
The primary modeling object in Plasmo.jl is the [`OptiGraph`](@ref). An `OptiGraph` is composed of [`OptiNode`](@ref)s (which represent self-contained optimization problems) which are connected by [`OptiEdge`](@ref)s
(which encapsulate [`LinkConstraint`](@ref)s that couple `OptiNodes`). The `OptiGraph` provides a modular approach to create optimization problems and provides
graph functions which can be used to manage model development, reveal inherent structures, and perform graph processing tasks such as partitioning.

The `OptiGraph` ultimately describes the following mathematical representation of an optimization problem:
```math
\begin{aligned}
    \min_{{\{x_n}\}_{n \in \mathcal{N}(\mathcal{G})}} & \quad \sum_{n \in \mathcal{N(\mathcal{G})}} f_n(x_n) \quad & (\textrm{Objective}) \\
    \textrm{s.t.} & \quad x_n \in \mathcal{X}_n,      \quad n \in \mathcal{N(\mathcal{G})}, \quad & (\textrm{Node Constraints})\\
    & \quad g_e(\{x_n\}_{n \in \mathcal{N}(e)}) = 0,  \quad e \in \mathcal{E(\mathcal{G})}. &(\textrm{Link Constraints})
\end{aligned}
```
In this formulation, ``\mathcal{G}`` represents the optigraph, ``{\{x_n}\}_{n \in \mathcal{N}(\mathcal{G})}`` describes a collection of decision
variables over the set of nodes (optinodes) ``\mathcal{N}(\mathcal{G})``, and ``x_n`` is the set of
decision variables on node ``n``. The objective function for the optigraph ``\mathcal{G}`` is given by a linear combination of objective functions on each optinode ``f_n(x_n)``.
The second equation represents constraints on each optinode ``\mathcal{N}(\mathcal{G})``, and the third equation represents the collection of
linking constraints associated with optiedges ``\mathcal{E}(\mathcal{G})``. The constraints of an optinode ``n`` are represented by the set ``\mathcal{X}_n`` while the linking constraints
that correspond to an edge ``e`` are represented by the vector function ``g_e(\{x_n\}_{n \in \mathcal{N}(e)})``.

From an implementation standpoint, an `OptiGraph` contains `OptiNode` and `OptiEdge` objects and extends much of the modeling functionality and syntax from [JuMP](https://github.com/jump-dev/JuMP.jl).


## Creating an OptiGraph
An `OptiGraph` does not require any arguments to construct:

```@meta
CurrentModule = Plasmo
DocTestSetup = quote
    using Plasmo
end
```

```jldoctest modeling
julia> graph1 = OptiGraph()
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
An optimizer can be specified using the [`set_optimizer`](@ref) function which supports any
[MathOptInterface.jl](https://github.com/jump-dev/MathOptInterface.jl) optimizer.  
For example, we could use the `Ipopt.Optimizer` from the Ipopt package as following:

```julia
julia> using Ipopt

julia> set_optimizer(graph1,Ipopt.Optimizer)
```

## Adding OptiNodes
The most effective way to add optinodes to an optigraph is by using the [`@optinode`](@ref) macro.  The below snippet adds the node `n1` to
the optigraph `graph1`.

```jldoctest modeling
julia> @optinode(graph1,n1)
OptiNode w/ 0 Variable(s) and 0 Constraint(s)
```
It is also possible to create sets of optinodes with a single call to [`@optinode`](@ref) like shown in the below code snippet.
Here, we create two more optinodes which returns the reference `nodes`. This macro call produces a `JuMP.DenseAxisArray` which
allows us to refer to each optinode using the produced index sets.  For example, `nodes[2]` and `nodes[3]` each return the corresponding
optinode.

```jldoctest modeling
julia> @optinode(graph1,nodes[2:3])
1-dimensional DenseAxisArray{OptiNode,1,...} with index sets:
    Dimension 1, 2:3
And data, a 2-element Vector{OptiNode}:
 OptiNode w/ 0 Variable(s) and 0 Constraint(s)
 OptiNode w/ 0 Variable(s) and 0 Constraint(s)

julia> nodes[2]
OptiNode w/ 0 Variable(s) and 0 Constraint(s)

julia> nodes[3]
OptiNode w/ 0 Variable(s) and 0 Constraint(s)
```
Each optinode supports adding variables, constraints, and an objective function.  Here we loop through each optinode in `graph1` using the [`all_nodes`](@ref) function
and we construct underlying model elements.
```jldoctest modeling
julia>  for node in getnodes(graph1)
            @variable(node,x >= 0)
            @variable(node, y >= 2)
            @constraint(node, x + y >= 3)
            @objective(node, Min, y)
        end
```

!!! note

     The [`OptiNode`](@ref) extends a `JuMP.AbstractModel` and supports the same `JuMP` macros such as `@variable`, `@constraint`, `@NLconstraint`, and `@objective`

Variables within an optinode can be accessed directly by indexing the associated symbol. This enclosed name-space is useful for
referencing variables on different optinodes when creating link-constraints or optigraph objective functions.
```jldoctest modeling
julia> n1[:x]
n1[:x]

julia> nodes[2][:x]
nodes[2][:x]
```

## Adding LinkConstraints
Link-constraints ([`LinkConstraint`](@ref)s) are linear constraints that couple variables across optinodes. The simplest way to create a link-constraint
is to use the `@linkconstraint` macro. This macro accepts the same input as the `@constraint` macro, but it requires variables to be on at least two different optinodes.

```jldoctest modeling
julia> @linkconstraint(graph1, n1[:x] + nodes[2][:x] + nodes[3][:x] == 3)
: n1[:x] + nodes[2][:x] + nodes[3][:x] = 3.0
```
We can also plot the graph structure of `graph1` (see [Plotting](@ref)) using both a graph and matrix layouts.

```@setup plot_example1
    using Plasmo
    graph1 = OptiGraph()
    @optinode(graph1,n1)
    @optinode(graph1,nodes[2:3])

    for node in getnodes(graph1)
        @variable(node,x >= 0)
        @variable(node, y >= 2)
        @constraint(node,x + y >= 3)
        @objective(node, Min, y)
    end

    @linkconstraint(graph1, n1[:x] + nodes[2][:x] + nodes[3][:x] == 3)
```

```@repl plot_example1
using Plots;

plt_graph = Plots.plot(graph1,node_labels = true, markersize = 30,labelsize = 15, linewidth = 4,layout_options = Dict(:tol => 0.01,:iterations => 2),plt_options = Dict(:legend => false,:framestyle => :box,:grid => false,:size => (400,400),:axis => nothing));

Plots.savefig(plt_graph,"graph1_layout.svg");

plt_matrix = Plots.spy(graph1,node_labels = true,markersize = 15);   

Plots.savefig(plt_matrix,"matrix1_layout.svg");
```
```@raw html
<img src="../graph1_layout.svg" alt="graph1" width="400"/>
```
```@raw html
<img src="../matrix1_layout.svg" alt="matrix1" width="400"/>
```

## Hierarchical Modeling with Subgraphs

A fundamental feature of using optigraphs is that it is possible to create subgraphs (i.e. sub-optigraphs) within an optigraph.  This enables a hierarchical style of modeling that retains its modular aspects.
Subgraphs are defined using the [`add_subgraph!`](@ref) function which embeds an optigraph as a subgraph within a higher level optigraph. This is demonstrated in the below snippets.  

First, we create two new optigraphs in the same fashion we did above.

```jldoctest modeling
julia> graph2 = OptiGraph();

julia> @optinode(graph2,nodes2[1:3]);

julia>  for node in getnodes(graph2)
            @variable(node, x >= 0)
            @variable(node, y >= 2)
            @constraint(node,x + y >= 5)
            @objective(node, Min, y)
        end

julia> @linkconstraint(graph2, nodes2[1][:x] + nodes2[2][:x] + nodes2[3][:x] == 5);

julia> graph3 = OptiGraph();

julia> @optinode(graph3,nodes3[1:3]);

julia>  for node in getnodes(graph3)
            @variable(node, x >= 0)
            @variable(node, y >= 2)
            @constraint(node,x + y >= 5)
            @objective(node, Min, y)
        end

julia> @linkconstraint(graph3, nodes3[1][:x] + nodes3[2][:x] + nodes3[3][:x] == 7);
```

Now we have three optigraphs (`graph1`,`graph2`, and `graph3`), each with their own local optinodes and linking constraints (which induce optiedges).  
These optigraphs can be embedded into a higher level optigraph with the following snippet:

```jldoctest modeling
julia> graph0 = OptiGraph()
OptiGraph:
local nodes: 0, total nodes: 0
local link constraints: 0, total link constraints 0
local subgraphs: 0, total subgraphs 0

julia> add_subgraph!(graph0,graph1)
OptiGraph:
local nodes: 0, total nodes: 3
local link constraints: 0, total link constraints 1
local subgraphs: 1, total subgraphs 1

julia> add_subgraph!(graph0,graph2)
OptiGraph:
local nodes: 0, total nodes: 6
local link constraints: 0, total link constraints 2
local subgraphs: 2, total subgraphs 2

julia> add_subgraph!(graph0,graph3)
OptiGraph:
local nodes: 0, total nodes: 9
local link constraints: 0, total link constraints 3
local subgraphs: 3, total subgraphs 3
```
Here, we see the distinction between local and global (total) elements. For instance, after we add all three subgraphs
the higher level `graph0`, we see that `graph0` contains 0 local optinodes, but contains 9 total optinodes which are elements of its subgraphs. This hierarchical distinction is also
made for linking constraints (i.e. optiedges), as well as subgraphs.  With this hierarhical style of modeling, subgraphs can be nested recursively such that an optigraph might contain
local subgraphs, and the highest level optigraph contains all of the subgraphs.

A key benefit of this hierarchical approach is that linking constraints can be expressed both locally and globally.  For instance, we can now add a linking constraint to `graph0` that
connects optinodes in its subgraphs like following:
```jldoctest modeling
julia> @linkconstraint(graph0,nodes[3][:x] + nodes2[2][:x] + nodes3[1][:x] == 10)
LinkConstraintRef(1, OptiEdge w/ 1 Constraint(s))

julia> println(graph0)
OptiGraph:
local nodes: 0, total nodes: 9
local link constraints: 1, total link constraints 4
local subgraphs: 3, total subgraphs 3
```
We now observe that `graph0` contains 1 local linking constraint, and 4 total linking constraints (by including its subgraphs).
Put another way, the local linking constraint in `graph0` is a global constraint that connects each of its subgraphs. This hierarchical style of modeling
facilitates the construction of optimization problems that include diverse model components.  For instance, a power system could be modeled separately from a
natural gas system and they could be coupled in a higher level combined optigraph.  The hierarchical structure also enables the use of distributed optimization solvers which
we discuss more in the [Solvers](@ref) section.

We can lastly plot the hierarchical optigraph and see the nested subgraph structure.

```@setup plot_example2
    using Plasmo
    graph1 = OptiGraph()
    @optinode(graph1,n1)
    @optinode(graph1,nodes[2:3])

    for node in getnodes(graph1)
        @variable(node,x >= 0)
        @variable(node, y >= 2)
        @constraint(node,x + y >= 3)
        @objective(node, Min, y)
    end

    @linkconstraint(graph1, n1[:x] + nodes[2][:x] + nodes[3][:x] == 3)

    graph2 = OptiGraph();

    @optinode(graph2,nodes2[1:3]);

    for node in getnodes(graph2)
        @variable(node, x >= 0)
        @variable(node, y >= 2)
        @constraint(node,x + y >= 5)
        @objective(node, Min, y)
    end

    @linkconstraint(graph2, nodes2[1][:x] + nodes2[2][:x] + nodes2[3][:x] == 5);

    graph3 = OptiGraph();

    @optinode(graph3,nodes3[1:3]);

    for node in getnodes(graph3)
        @variable(node, x >= 0)
        @variable(node, y >= 2)
        @constraint(node,x + y >= 5)
        @objective(node, Min, y)
    end

    @linkconstraint(graph3, nodes3[1][:x] + nodes3[2][:x] + nodes3[3][:x] == 7)

    graph0 = OptiGraph()
    add_subgraph!(graph0,graph1)
    add_subgraph!(graph0,graph2)
    add_subgraph!(graph0,graph3)

    @linkconstraint(graph0,nodes[3][:x] + nodes2[2][:x] + nodes3[1][:x] == 10)
```

```@repl plot_example2
using Plots

for (i,node) in enumerate(all_nodes(graph0))
    node.label = "n$i"
end

plt_graph0 = Plots.plot(graph0,node_labels = true,markersize = 60,labelsize = 30,linewidth = 4,subgraph_colors = true,
layout_options = Dict(:tol => 0.001,:C => 2, :K => 4, :iterations => 5));

Plots.savefig(plt_graph0,"graph0_layout.svg");

plt_matrix0 = Plots.spy(graph0,node_labels = true,subgraph_colors = true,markersize = 16);

Plots.savefig(plt_matrix0,"matrix0_layout.svg");
```
```@raw html
<img src="../graph0_layout.svg" alt="graph0" width="400"/>
```
```@raw html
<img src="../matrix0_layout.svg" alt="matrix0" width="400"/>
```

## Query OptiGraph Attributes
There are a few primary function which can be used to query optigraph attributes. `getnodes` can be used to retrieve an array of
the local optinodes in an optigraph, whereas `all_nodes` will recursively retrieve all of the optinodes in an optigraph, including the nodes in its subgraphs.

```jldoctest modeling
julia> getnodes(graph1)
3-element Array{OptiNode,1}:
 OptiNode w/ 2 Variable(s)
 OptiNode w/ 2 Variable(s)
 OptiNode w/ 2 Variable(s)

julia> getnodes(graph0)
0-element Array{OptiNode,1}

julia> all_nodes(graph0)
9-element Array{OptiNode,1}:
 OptiNode w/ 2 Variable(s)
 OptiNode w/ 2 Variable(s)
 OptiNode w/ 2 Variable(s)
 OptiNode w/ 2 Variable(s)
 OptiNode w/ 2 Variable(s)
 OptiNode w/ 2 Variable(s)
 OptiNode w/ 2 Variable(s)
 OptiNode w/ 2 Variable(s)
 OptiNode w/ 2 Variable(s)

```

It is possible to query for optiedges, linking constraints, and subgraphs in the same way. We can query optiedges:
```jldoctest modeling
julia> getedges(graph1)
1-element Array{OptiEdge,1}:
 OptiEdge w/ 1 Constraint(s)

julia> getedges(graph0)
1-element Array{OptiEdge,1}:
 OptiEdge w/ 1 Constraint(s)

julia> all_edges(graph0)
4-element Array{OptiEdge,1}:
 OptiEdge w/ 1 Constraint(s)
 OptiEdge w/ 1 Constraint(s)
 OptiEdge w/ 1 Constraint(s)
 OptiEdge w/ 1 Constraint(s)
```
query linking constraints:
```jldoctest modeling
julia> getlinkconstraints(graph1)
1-element Array{LinkConstraint,1}:
 LinkConstraint: x + x + x, MathOptInterface.EqualTo{Float64}(3.0)

julia> getlinkconstraints(graph0)
1-element Array{LinkConstraint,1}:
 LinkConstraint: x + x + x, MathOptInterface.EqualTo{Float64}(10.0)

julia> all_linkconstraints(graph0)
4-element Array{LinkConstraint,1}:
 LinkConstraint: x + x + x, MathOptInterface.EqualTo{Float64}(3.0)
 LinkConstraint: x + x + x, MathOptInterface.EqualTo{Float64}(5.0)
 LinkConstraint: x + x + x, MathOptInterface.EqualTo{Float64}(7.0)
 LinkConstraint: x + x + x, MathOptInterface.EqualTo{Float64}(10.0)
```
and query subgraphs:
```jldoctest modeling
julia> getsubgraphs(graph0)
3-element Array{AbstractOptiGraph,1}:
 OptiGraph:
local nodes: 3, total nodes: 3
local link constraints: 1, total link constraints 1
local subgraphs: 0, total subgraphs 0

 OptiGraph:
local nodes: 3, total nodes: 3
local link constraints: 1, total link constraints 1
local subgraphs: 0, total subgraphs 0

 OptiGraph:
local nodes: 3, total nodes: 3
local link constraints: 1, total link constraints 1
local subgraphs: 0, total subgraphs 0
```

## Other OptiGraph Modeling Features

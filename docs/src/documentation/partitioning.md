# Partitioning and Graph Operations
The [Modeling](@ref) section describes how to construct optigraphs using a bottom-up approach.  Specifically, we showed how to
to use [Hierarchical Modeling](@ref) with subgraphs to create multi-level optigraphs. This part of the documentation deals with creating optigraphs using a top-down approach.
Specifically, we show how to construct subgraphs using graph partitions and show how `Plasmo.jl` interfaces with standard graph partitioning tools such
as [Metis](https://github.com/JuliaSparse/Metis.jl) and [KaHyPar](https://github.com/kahypar/KaHyPar.jl).

## Example Problem: Dynamic Optimization
To help demonstrate graph partitioning capabilities in `Plasmo.jl`, we instantiate a simple optimal control problem described by the following equations. In this problem, ``x`` is a vector of states and ``u`` is a vector of control
actions which are both indexed over the set of time indices ``t \in \{1,...,T\}``. The objective function minimizes the state trajectory with minimal control effort (energy), the second equation describes the
state dynamics, and the third equation defines the initial condition. The last two equations define limits on the state and control actions.

```@meta
    DocTestSetup = quote
    using Plasmo

    T = 100          #number of time points
    d = sin.(1:T)    #disturbance vector

    graph = OptiGraph()
    @optinode(graph,state[1:T])
    @optinode(graph,control[1:T-1])

    for node in state
        @variable(node,x)
        @constraint(node, x >= 0)
        @objective(node,Min,x^2)
    end
    for node in control
        @variable(node,u)
        @constraint(node, u >= -1000)
        @objective(node,Min,u^2)
    end

    @linkconstraint(graph,[i = 1:T-1],state[i+1][:x] == state[i][:x] + control[i][:u] + d[i])
    n1 = state[1]
    @constraint(n1,n1[:x] == 0)
end
```

```math
\begin{aligned}
    \min_{\{ x,u \}} & \sum_{t = 1}^T x_t^2 + u_t^2  & \\
    \textrm{s.t.} \quad & x_{t+1} = x_t + u_t + d_t, \quad t \in \{1,...,T-1\}  & \\
    & x_{1} = 0  &\\
    & x_t \ge 0, \quad t \in \{1,...,T\}\\
    & u_t \ge -1000, \quad t \in \{1,...,T-1\}
\end{aligned}
```

This snippet shows how to construct the optimal control problem in `Plasmo.jl` as described in [Modeling](@ref). We create an optigraph, add optinodes which represent states and controls at each time period, we set
objective functions for each optinode, and we use linking constraints to describe the dynamics.

```julia
using Plasmo

T = 100          #number of time points
d = sin.(1:T)    #disturbance vector

graph = OptiGraph()
@optinode(graph,state[1:T])
@optinode(graph,control[1:T-1])

for node in state
    @variable(node,x)
    @constraint(node, x >= 0)
    @objective(node,Min,x^2)
end
for node in control
    @variable(node,u)
    @constraint(node, u >= -1000)
    @objective(node,Min,u^2)
end

@linkconstraint(graph,[i = 1:T-1],state[i+1][:x] == state[i][:x] + control[i][:u] + d[i])
n1 = state[1]
@constraint(n1,n1[:x] == 0)
```
When we print the newly created optigraph for our optimal control problem, we see it contains about 200 optinodes (one for each state and control) and contains almost 100 linking constraints (which couple the time periods).
```jldoctest hypergraph
julia> println(graph)
OptiGraph:
local nodes: 199, total nodes: 199
local link constraints: 99, total link constraints 99
local subgraphs: 0, total subgraphs 0
```

```@meta
    DocTestSetup = nothing
```

We can also plot the resulting optigraph (see [Plotting](@ref)) which produces a simple chain, but otherwise there is no real structure in the problem as we have modeled it.
```@setup plot_chain
    using Plasmo

    T = 100         
    d = sin.(1:T)   

    graph = OptiGraph()
    @optinode(graph,state[1:T])
    @optinode(graph,control[1:T-1])

    for node in state
        @variable(node,x)
        @constraint(node, x >= 0)
        @objective(node,Min,x^2)
    end
    for node in control
        @variable(node,u)
        @constraint(node, u >= -1000)
        @objective(node,Min,u^2)
    end

    @linkconstraint(graph,[i = 1:T-1],state[i+1][:x] == state[i][:x] + control[i][:u] + d[i])
    n1 = state[1]
    @constraint(n1,n1[:x] == 0)
```

```@repl plot_chain
using Plots; pyplot()
plt_chain = plt_graph4 = plot(graph,layout_options = Dict(:tol => 0.1,:iterations => 500), linealpha = 0.2,markersize = 6)
Plots.savefig(plt_chain,"chain_layout.svg");

plt_chain_matrix = spy(graph);
Plots.savefig(plt_chain_matrix,"chain_layout_matrix.svg");
```

```@raw html
<img src="chain_layout.svg" alt="chain" width="400"/>
```

```@raw html
<img src="chain_layout_matrix.svg" alt="chain_matrix" width="400"/>
```

## Partitioning OptiGraphs
At its core, the [`OptiGraph`] is a hypergraph and can thus naturally exploit hypergraph partitioning tools.  For our example here we demonstrate how to use hypergraph partitioning (using [KaHyPar](https://github.com/kahypar/KaHyPar.jl)),
but `Plasmo.jl` also facilitates using standard graph partitioning algorithms  (a hypergraph can be projected to various standard graph representations) or partitioning by manually defining partition vectors.
The below snippet uses the [`gethypergraph`](@ref) function which returns a [`HyperGraph`](@ref) object and a `hyper_map` (a Julia dictionary) which maps hypernodes and hyperedges back to the original optigraph.

```jldoctest hypergraph
julia> hypergraph,hyper_map = gethypergraph(graph);

julia> println(hypergraph)
Hypergraph: (199 , 99)
```

```@meta
    DocTestSetup = quote
    using Plasmo
    using KaHyPar

    T = 100         
    d = sin.(1:T)   

    graph = OptiGraph()
    @optinode(graph,state[1:T])
    @optinode(graph,control[1:T-1])

    for node in state
        @variable(node,x)
        @constraint(node, x >= 0)
        @objective(node,Min,x^2)
    end
    for node in control
        @variable(node,u)
        @constraint(node, u >= -1000)
        @objective(node,Min,u^2)
    end

    @linkconstraint(graph,[i = 1:T-1],state[i+1][:x] == state[i][:x] + control[i][:u] + d[i])
    n1 = state[1]
    @constraint(n1,n1[:x] == 0)

    hypergraph,hyper_map = gethypergraph(graph)
    partition_vector = KaHyPar.partition(hypergraph,8,configuration = :connectivity,imbalance = 0.01)
    partition = Partition(graph,partition_vector,hyper_map)
    make_subgraphs!(graph,partition)
    end
```

With our `hypergraph` we can now use `KaHyPar` to perform hypergraph partitioning in the next snippet which returns a `partition_vector` . Each index in the `partition_vector` corresponds to a
hypernode index in `hypergraph`, and each value denotes which partition the hypernode belongs to.  So in our example, `partition_vector` contains 199 elements which can take on integer values between 0 and 7 (for 8 total partitions). Once we have a `partition_vector`, we can create a [`Partition`](@ref) object which describes sets (partitions) of optinodes and optiedges, as well as the shared optinodes and optiedges that cross partitions.
We can lastly use the produced `partition` (a `Partition` object) to formulate subgraphs in our original optigraph (`graph`) using [`make_subgraphs!`](@ref). After doing so,
we see that our `graph` now contains 8 subgraphs with 7 linking constraints that correspond to the optiedges that cross partitions (i.e. connect subgraphs).

```julia
julia> using KaHyPar

julia> partition_vector = KaHyPar.partition(hypergraph,8,configuration = :connectivity,imbalance = 0.01);

julia> partition = Partition(graph,partition_vector,hyper_map);

julia> make_subgraphs!(graph,partition);
```

```jldoctest partitioning
julia> println(length(partition_vector))
199

julia> println(partition)
    OptiGraph Partition w/ 8 subpartitions

julia> println(length(getsubgraphs(graph)))
8

julia> num_linkconstraints(graph)
7
```

```@setup plot_chain_partition
    using Plasmo
    using KaHyPar
    using Plots; pyplot()

    T = 100         
    d = sin.(1:T)   

    graph = OptiGraph()
    @optinode(graph,state[1:T])
    @optinode(graph,control[1:T-1])

    for node in state
        @variable(node,x)
        @constraint(node, x >= 0)
        @objective(node,Min,x^2)
    end
    for node in control
        @variable(node,u)
        @constraint(node, u >= -1000)
        @objective(node,Min,u^2)
    end

    @linkconstraint(graph,[i = 1:T-1],state[i+1][:x] == state[i][:x] + control[i][:u] + d[i])
    n1 = state[1]
    @constraint(n1,n1[:x] == 0)

    hypergraph,hyper_map = gethypergraph(graph);
    partition_vector = KaHyPar.partition(hypergraph,8,configuration = :connectivity,imbalance = 0.01);
    partition = Partition(graph,partition_vector,hyper_map);
    make_subgraphs!(graph,partition);
```

If we plot the partitioned optigraph, it reveals eight distinct partitions and
the coupling between them. The plots show that the partitions are well-balanced and the matrix visualization shows the problem is reordered into a banded structure that is typical of dynamic
optimization problems.

```@repl plot_chain_partition
plt_chain_partition = plot(graph,layout_options = Dict(:tol => 0.01, :iterations => 500),linealpha = 0.2,markersize = 6,subgraph_colors = true);
Plots.savefig(plt_chain_partition,"chain_layout_partition.svg");

plt_chain_matrix_partition = spy(graph,subgraph_colors = true);
Plots.savefig(plt_chain_matrix_partition,"chain_layout_matrix_partition.svg");
```

```@raw html
<img src="chain_layout_partition.svg" alt="chain_partition" width="400"/>
```

```@raw html
<img src="chain_layout_matrix_partition.svg" alt="chain_matrix_partition" width="400"/>
```

## Aggregating OptiGraphs
Subgraphs can be converted into stand-alone optinodes using the using the [`aggregate`](@ref) function. This is important from a solver stand-point because optinodes represent solvable subproblems
which can be communicated to decomposition algorithms. This aggregation step also takes place when using standard optimization solvers with `Plasmo.jl`, such as `Ipopt` wherein the optigraph is aggregated into a
single optinode and solved using the underlying `JuMP` interface. In the snippet below, we aggregate
our optigraph that contains 8 subgraphs.  We include the argument `0` which specifies how many subgraph levels to retain.  In this case,
`0` means we aggregate subgraphs at the highest level so `graph` contains only new aggregated optinodes. For hierarchical graphs with many levels,
we can define how many subgraph levels we wish to retain. The function returns a new aggregated graph (`aggregate_graph`), as well as
`reference_map` which maps variables in `aggregate_graph` to the original optigraph `graph`.


```jldoctest partitioning
julia> aggregate_graph,reference_map = aggregate(graph,0);
Creating Combined OptiGraph with a maximum subgraph depth of 0

julia> println(aggregate_graph)
OptiGraph:
local nodes: 8, total nodes: 8
local link constraints: 7, total link constraints 7
local subgraphs: 0, total subgraphs 0
```

```@setup plot_chain_aggregate
    using Plasmo
    using KaHyPar
    using Plots; pyplot()

    T = 100         
    d = sin.(1:T)   

    graph = OptiGraph()
    @optinode(graph,state[1:T])
    @optinode(graph,control[1:T-1])

    for node in state
        @variable(node,x)
        @constraint(node, x >= 0)
        @objective(node,Min,x^2)
    end
    for node in control
        @variable(node,u)
        @constraint(node, u >= -1000)
        @objective(node,Min,u^2)
    end

    @linkconstraint(graph,[i = 1:T-1],state[i+1][:x] == state[i][:x] + control[i][:u] + d[i])
    n1 = state[1]
    @constraint(n1,n1[:x] == 0)

    hypergraph,hyper_map = gethypergraph(graph);
    partition_vector = KaHyPar.partition(hypergraph,8,configuration = :connectivity,imbalance = 0.01);
    partition = Partition(graph,partition_vector,hyper_map);
    make_subgraphs!(graph,partition);

    aggregate_graph,reference_map = aggregate(graph,0);
```

We can lastly plot the aggregated graph structure which simply shows 8 optinodes with 7 linking constraints.
```@repl plot_chain_aggregate
plt_chain_aggregate = plot(aggregate_graph,layout_options = Dict(:tol => 0.01,:iterations => 10),node_labels = true,markersize = 30,labelsize = 20,node_colors = true);
Plots.savefig(plt_chain_aggregate,"chain_layout_aggregate.svg");

plt_chain_matrix_aggregate = spy(aggregate_graph,node_labels = true,node_colors = true);
Plots.savefig(plt_chain_matrix_aggregate,"chain_layout_matrix_aggregate.svg");
```

```@raw html
<img src="chain_layout_aggregate.svg" alt="chain_aggregate" width="400"/>
```

```@raw html
<img src="chain_layout_matrix_aggregate.svg" alt="chain_matrix_aggregate" width="400"/>
```

## Methods

```@docs
Partition
make_subgraphs!
aggregate
expand
Plasmo.neighborhood
```

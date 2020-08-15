# Partitioning
One of the key aspects behind modeling with optigraphs is that they facilitate graph operations such as partitioning.  
The optigraph structure can exploit popular graph partitioning approaches such as those used in [Metis](https://github.com/JuliaSparse/Metis.jl) or [KaHyPar](https://github.com/kahypar/KaHyPar.jl).

## OptiGraph Representations
To partition an optigraph, we first need to transform it into an appropriate graph representation that reflects the partitioning algorithm.
An optigraph most closely adheres to a hypergraph representation wherein its optinodes represent hypernodes and its optiedges correspond to hyperedges that connect two or more optinodes (hypernodes).

## Example Problem: Dynamic Optimization
To help demonstrate partitioning capabilities, we instantiate a simple optimal control problem with following code snippet. Here, ``x`` is a vector of states and ``u`` is a vector of control actions which are both
indexed over the set of time indices ``t \in \{1,...,T\}``. The objective function minimizes the state trajectory with minimal control effort (energy), the second equation describes the
state dynamics, and the third equation defines the initial condition.

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

If we plot the resulting optigraph (see [Plotting](@ref)) we obtain a simple simple chain, but otherwise there is no real structure in the problem.
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
```

```@raw html
<img src="chain_layout.svg" alt="chain" width="400"/>
```

### Hypergraph Representation
Before we partition the optigraph, we need to cast into a

```jldoctest hypergraph
julia> hypergraph,hyper_map = gethypergraph(graph);

julia> println(hypergraph)
Hypergraph: (199 , 99)
```

## Partitioning OptiGraphs
An optigraph can be partitioned into a set of

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
```

## Methods

```@docs
Partition
make_subgraphs!
```

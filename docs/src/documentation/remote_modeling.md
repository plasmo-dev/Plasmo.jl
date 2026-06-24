# Modeling with RemoteOptiGraphs

Further details on the RemoteOptiGraph are given in the manuscript ["A Graph-Based, Distributed Memory, Modeling Abstraction for Optimization"](https://arxiv.org/abs/2511.14966). Following the notation of this work, the RemoteOptiGraph is defined mathematically below for some RemoteOptiGraph $\mathcal{RG}(\mathcal{G}, \{\mathcal{RG}_{ i}\}_{i \in \{1, ..., N^{\mathcal{RG}} \}}, \mathcal{E}^{IW}, w)$. Here, $\mathcal{RG}$ is a RemoteOptiGraph, $\mathcal{SG}(\mathcal{RG})$ is the set of subgraphs on $\mathcal{RG}$, $\mathcal{N}(g)$ is the set of nodes on graph $g$, and $\mathcal{E}(g)$ is the set of edges on graph $g$.

```math
\begin{aligned}
    \min &\; f\left(\{\boldsymbol{x}_n \}_{n \in \mathcal{N}(\mathcal{G})}\right) + \sum_{g \in \mathcal{SG}(\mathcal{RG})} f_g\left(\{\boldsymbol{x}_n \}_{n \in \mathcal{N}(g)}\right) & (\textrm{Objective})\\
    \textrm{s.t.} &\; \boldsymbol{x}_n \in \mathcal{X}_n, \quad n \in \left(\bigcup_{g \in \mathcal{SG}(\mathcal{RG})} \mathcal{N}(g) \right) \cup \mathcal{N}(\mathcal{G}) & (\textrm{Node Constraints})\\
    &\; g_e(\{\boldsymbol{x}_n\}_{n \in \mathcal{N}(e)})\geq 0, \quad e \in\left(\bigcup_{g \in \mathcal{SG}(\mathcal{RG})} \mathcal{E}(g) \right) \cup \mathcal{E}(\mathcal{G}) & (\textrm{Local Link Constraints})\\
    &\; g_e(\{\boldsymbol{x}_n\}_{n \in \mathcal{N}(e)})\geq 0, \quad e \in \mathcal{E}^{IW}(\mathcal{RG}) & (\textrm{Inter-Worker Link Constraints}).
\end{aligned}
```

Note that the objective function is separable between the subgraphs. 


## Building Remote vs. Building Locally

The RemoteOptiGraph is designed so as to capture problem structure for problems distributed to multiple workers. Different modeling paradigms could be used for constructing a RemoteOptiGraph, and users may choose different approaches to construct the same problem. For instance, a user could build a graph locally and then distribute to remote processors, or they could directly construct the graph on the remote processors (see suggestion #3 below). For large-scale applications, it is recommended that users build the graph remotely to avoid serialization time and to potentially better parallelize model construction. 

For benchmarking, Plasmo does support building an OptiGraph locally and then distributing its graphs to a remote worker via the `distribute_graph` function. This function is not recommended for very large models, but an example of its use is given below.

```julia
using Distributed
addprocs(1)
@everywhere begin
    using Plasmo, HiGHS, Distributed
end

# Generate toy graph
g = OptiGraph()
g1 = OptiGraph()
g2 = OptiGraph()

@optinode(g1, n1); @optinode(g2, n2);
@variable(n1, 0 <= x[1:10]); @variable(n2, 0 <= y[1:10]);
@objective(n1, Min, sum(x[i] * i for i in 1:10))
@objective(n2, Min, sum(y));

add_subgraph(g, g1)
add_subgraph(g, g2)

@linkconstraint(g, [i in 1:10], n1[:x][i] + n2[:y][i] >= 5)

# Distribute both g1 and g2 to remote worker 2
rg = distribute_graph(g, [2, 2])

remote_subgraphs = local_subgraphs(rg)
rg1 = remote_subgraphs[1] # corresponds to g1
rg2 = remote_subgraphs[2] # corresponds to g2

rn1 = rg1[:n1] # RemoteNodeRef for n1
rn2 = rg2[:n2] # RemoteNodeRef for n2

rx = rn1[:x] # vector of RemoteVariableRef for x
ry = rn2[:y] # vector of RemoteVariableRef for y
```

## Performance Tips and Suggestions

#### 1. Remember that each macro call is a separate call to the remote

Plasmo's `RemoteOptiGraph` object can be used in place of a normal `OptiGraph` object in most code as these functions have been extended to handle the `RemoteOptiGraph`. For large-scale models, or code with lots of macro calls, it may not be ideal to have lots of macro (or other function) calls. A challenge of distributed programming is that communication between workers has an overhead cost, and the more calls to remote workers, the slower code will be. Consequently, it is recommended that the user be wise in how they call different functions on the `RemoteOptiGraph`. 

#### 2. Remember that some functions serialize larger objects between workers than other functions

The larger the objects that are shared across workers, the slower the code will be, and not all functions will use the same amount of overhead. As an example, calling `all_variables` on a `RemoteOptiGraph` will create `RemoteVariableRef` objects for every variable on the graph, and it will share between the workers information for creating all variables (names as symbols and indices essentially as integers). In an ordinary JuMP model, calling `length(all_variables(m))` for a model `m` may not have noticeable overhead to it if a user only calls this once or twice, but calling `length(all_variables(g))` for a remote graph `g` may be noticeably slower since it is building `RemoteVariableRef`s for all variables on the graph. While it is best practice for both JuMP models and Plasmo `RemoteOptiGraph`s, using `JuMP.num_variables(g)` will be proportionally far more efficient in the case of the `RemoteOptiGraph` than it would be for a JuMP model.

#### 3. Consider defining custom build functions

As noted in 1., lots of macro calls and other function calls can slow down the code for especially large models. One option to avoid this is to build the graph directly on the remote worker inside a remote call or `@spawnat` call. For instance, the user could define a function that takes an `OptiGraph` object and constructs a large optimization problem on it for every worker, such as the following: 

```julia
using Plasmo, Distributed, DistributedArrays
addprocs(1)

@everywhere begin
    function build_subgraph_remotely(graph::OptiGraph)
        @optinode(graph, n[1:10])
        @variable(n[1], x[1:10] >= 0)
        @objective(n[1], Min, sum(x))
        #etc.
    end
end
```

The user can then call this on a remote graph by doing the following

```julia
rgraph = RemoteOptiGraph(worker = 2) # Define a RemoteOptiGraph on worker 2

darray = rgraph.graph # Get the DistributedArray containing the OptiGraph

@spawnat rgraph.worker begin
    lgraph = localpart(darray)[1] # On the remote worker, retrieve the local graph
    build_subgraph_remotely(lgraph) # run the function that was defined on this worker via the @everywhere call
end
```

This will add to the OptiGraph remotely so that there are not large amounts of remote calls. The user can still access the objects on this graph via `all_variables`, `all_nodes`, or by indexing for names. As with an `OptiGraph`, you can access objects by their symbols. For instance, calling `rgraph[:n]` returns a set of `RemoteNodeRef`s that correspond to the `n[1:10]` defined in the `build_subgraph_remotely` function. Similarly, we can call `rgraph[:n][1][:x][1]` to get a `RemoteVariableRef` that corresponds to a variable stored on the graph on the remote worker. 
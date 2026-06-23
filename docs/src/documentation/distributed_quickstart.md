# Distributed OptiGraph QuickStart

In this quickstart, we give an example of how to build a `RemoteOptiGraph` in Plasmo.jl and then give several suggestions for best practices. 

## Instantiating a RemoteOptiGraph

The `RemoteOptiGraph` object can be instantiated by calling `RemoteOptiGraph(worker = workerid)` where `workerid` is the index of a remote worker that has been added to the main process. The `RemoteOptiGraph` object contains a DistributedArray.jl object that stores a reference to the array on the main worker and places the actual data of the array on a remote worker or workers. In the case of Plasmo, this is only a length one array, and an `OptiGraph` is stored in this DistributedArray on worker `workerid`. 


```julia
# Load in packages
using Plasmo, Distributed, JuMP, HiGHS, Ipopt

# Add a new remote processor
if nprocs() == 1
    addprocs(1)
end

# Load packages on the remote worker
@everywhere begin
    using Plasmo, JuMP, Distributed, HiGHS, Ipopt
end

# Instantiate optigraph on worker 2
rg = Plasmo.RemoteOptiGraph(worker=2)

```

## Constructing the RemoteOptiGraph

Functions in Plasmo and JuMP have been extended to work with Plasmo's `RemoteOptiGraph`s. For instance, macros for adding nodes, variables, constraints, expressions, linking constraints, and objectives have all been extended to work with the `RemoteOptiGraph`. Consequently, a user can build their graph remotely using the same functions they would for a normal, shared-memory `OptiGraph`. Below, we give a code snippet showing how a user can build the graph remotely. 

```julia

# Add nodes to the remote optigraph
# n1 and n2 are accesible on the main worker and are `RemoteNodeRef`s
@optinode(rg, n1)
@optinode(rg, n2)

# Add variables to the nodes
@variable(n1, x)
@variable(n1, y)
@variable(n2, z >= 0)

```

The `@optinode` call adds a `OptiNode` to the `OptiGraph` stored on worker 2 and returns a `RemoteNodeRef` corresponding to that `OptiNode`. The `@variable` call adds a variable to that corresponding `OptiNode` and returns a `RemoteVariableRef`. One note to make is that these remote reference objects are stored on the main worker and correspond to the standard objects stored on the remote worker. For instance, in the above code, `n1` is a `RemoteNodeRef` and `x1` is a `RemoteVariableRef` that both "live" on the main worker. 

Functions have been extended for working with these objects as you would with a `Plasmo.NodeVariableRef`, such that a user can call `fix(x1, 0)` (which is being called on the `RemoteVariableRef`) to fix the value of the _actual_ `NodeVariableRef` which `x1` corersponds to. 
```julia

# Many JuMP functions are extended to work with remote optigraphs
all_vars = JuMP.all_variables(rg)
JuMP.fix(x, 0)
```

Constraints (local and linking) operate as they would for a standard `OptiGraph`. They likewise return reference objects for their corresponding objects on the worker.

```julia
# Link constraints can be named and can link within a graph
# This link constraint creates a constraint on a `RemoteEdgeRef`
@linkconstraint(rg, lc1, x + rg[:n2][:z] <= 1)

# Linear, quadratic, and nonlinear constraints are all supported and can be named
@constraint(n1, n1_con, x + y <= 2); #linear constraint
@constraint(n1, x^2 + y <= 4); # quadratic constraint
@constraint(n1, cos(x) + y^2*x >= 1); #nonlinear constraint
```

Expressions and objectives can also be added via macros

```julia
# Expressions can be defined on nodes and remote optigraphs
@expression(n1, n1_expr, x + 2 * y)
@expression(rg, rg_expr, x + y + z)

# Add objective function
@objective(rg, Min, x + sin(y) + z^2)
```

An optimizer can be set and `optimize!` can be called on a `RemoteOptiGraph`. Plasmo goes to the worker and calls `optimize!` on the corresponding graph.

```julia
# Set optimizer on the graph on the remote worker
set_optimizer(rg, Ipopt.Optimizer)

# solve the graph
optimize!(rg)
```

## Creating Hierarchical RemoteOptiGraphs

As with a normal `OptiGraph`, the `RemoteOptiGraph` supports nesting other subgraphs within it. Each `RemoteOptiGraph` contains a vector of subgraphs called `subgraphs` and a reference to a parent graph called `parent_graph`. New subgraphs can be added to an existing `RemoteOptiGraph` via the function `add_subgraph`. Note that subgraphs or parent graphs do not need to be stored on the same remote worker as the other `RemoteOptiGraph`s. Subgraphs can easily be added to this problem, as shown below. 

```julia
# Define another graph and add nodes
rg2 = Plasmo.RemoteOptiGraph(worker = 2)

# Add nodes and variables
@optinode(rg2, n3)
@optinode(rg2, n4)

@variable(n3, x3)
@variable(n3, y3)
@variable(n4, z4)

# Add subgraphs to `rg` using `add_subgraph`
Plasmo.add_subgraph(rg, rg2)

# A new graph can be directly instantiated as a subgraph on `rg`
# by passing the worker index you want to build the graph on
rg3 = Plasmo.add_subgraph(rg, worker = 2)

# Add nodes and variables
@optinode(rg3, n5)
@variable(n5, x5)

# Link constraints can be added between subgraphs
# These are stored as constraints on `InterWorkerEdges
@linkconstraint(rg, x + x3 + rg3[:n5][:x5] == 0);
```

Two types of edges exist for `RemoteOptiGraph`s. The first is an `RemoteEdgeRef` which represents an edge stored on the remote worker inside the `OptiGraph`. In contrast, the `InterWorkerEdge` is an edge stored directly on the `RemoteOptiGraph` which connects the `OptiGraph` stored remotely with other subgraphs stored on the `RemoteOptiGraph`, or they connect multiple subgraphs stored on the `RemoteOptiGraph`.

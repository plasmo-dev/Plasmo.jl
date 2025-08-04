# Distributed OptiGraph QuickStart

In this quickstart, we give an example of how to build a `RemoteOptiGraph` in Plasmo.jl and then give several suggestions for best practices. 

The `RemoteOptiGraph` object can be instantiated by calling `RemoteOptiGraph(worker = workerid)` where `workerid` is the index of a remote worker that has been added to the main process. The `RemoteOptiGraph` object contains a DistributedArray.jl object that stores a reference to the array on the main worker and places the actual data of the array on a remote worker or workers. In the case of Plasmo, this is only a length one array, and an `OptiGraph` is stored in this DistributedArray on worker `workerid`. 

As with a normal `OptiGraph`, the `RemoteOptiGraph` supports nesting other subgraphs within it. Each `RemoteOptiGraph` contains a vector of subgraphs called `subgraphs` and a reference to a parent graph called `parent_graph`. New subgraphs can be added to an existing `RemoteOptiGraph` via the function `add_subgraph`. Note that subgraphs or parent graphs do not need to be stored on the same remote worker as the other `RemoteOptiGraph`s. 

Functions in Plasmo and JuMP have been extended to work with Plasmo's `RemoteOptiGraph`s. For instance, macros for adding nodes, variables, constraints, expressions, linking constraints, and objectives have all been extended to work with the `RemoteOptiGraph`. Consequently, a user can build their graph remotely using the same functions they would for a normal, shared-memory `OptiGraph`. Below, we give a code snippet showing how a user can build the graph remotely. 

```jldoctest; doctest=false
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

# Add nodes to the remote optigraph
# n1 and n2 are accesible on the main worker and are `RemoteNodeRef`s
@optinode(rg, n1)
@optinode(rg, n2)

# Add variables to the nodes
@variable(n1, x)
@variable(n1, y)
@variable(n2, z >= 0)

# Many JuMP functions are extended to work with remote optigraphs
all_vars = JuMP.all_variables(rg)
JuMP.fix(x, 0)

# Link constraints can be named and can link within a graph
# This link constraint creates a constraint on a `RemoteEdgeRef`
@linkconstraint(rg, lc1, x + rg[:n2][:z] <= 1)

# Linear, quadratic, and nonlinear constraints are all supported and can be named
@constraint(n1, n1_con, x + y <= 2); #linear constraint
@constraint(n1, x^2 + y <= 4); # quadratic constraint
@constraint(n1, cos(x) + y^2*x >= 1); #nonlinear constraint

# Expressions can be defined on nodes and remote optigraphs
@expression(n1, n1_expr, x + 2 * y)
@expression(rg, rg_expr, x + y + z)

# Add objective function
@objective(rg, Min, x + sin(y) + z^2)

# Set optimizer on the graph on the remote worker
set_optimizer(rg, Ipopt.Optimizer)

# solve the graph
optimize!(rg)
```

Subgraphs can easily be added to this problem, as shown below. 

```jldoctest; doctest=false
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
# These are stored as constraints on `RemoteOptiEdges
@linkconstraint(rg, x + x3 + rg3[:n5][:x5] == 0);
```

One note to make is that Plasmo returns light references to objects that are actually stored on the remote worker. For instance, in the above code, `n1` is a `RemoteNodeRef` that is stored on the main worker, and `x1` is a `RemoteVariableRef` that likewise lives on the remote. functions have been extended for working with these objects as you would with a `Plasmo.NodeVariableRef`, such that a user can call `fix(x1, 0)` (which is being called on the `RemoteVariableRef`) to fix the value of the _actual_ `NodeVariableRef` which `x1` corersponds to. 

In addition, two types of edges exist for `RemoteOptiGraph`s. The first is an `RemoteEdgeRef` which represents an edge stored on the remote worker inside the `OptiGraph`. In contrast, the `RemoteOptiEdge` is an edge stored directly on the `RemoteOptiGraph` which connects the `OptiGraph` stored remotely with other subgraphs stored on the `RemoteOptiGraph`, or they connect multiple subgraphs stored on the `RemoteOptiGraph`. 

## Performance Tips and Suggestions

#### 1. Remember that each macro call is a separate call to the remote

Plasmo's `RemoteOptiGraph` object can be used in place of a normal `OptiGraph` object in most code as these functions have been extended to handle the `RemoteOptiGraph`. For large-scale models, or code with lots of macro calls, it may not be ideal to have lots of macro (or other function) calls. A challenge of distributed programming is that communication between workers has an overhead cost, and the more calls to remote workers, the slower code will be. Consequently, it is recommended that the user be wise in how they call different functions on the `RemoteOptiGraph`. 

#### 2. Remember that some functions serialize larger objects between workers than other functions

The larger the objects that are shared across workers, the slower the code will be, and not all functions will use the same amount of overhead. As an example, calling `all_variables` on a `RemoteOptiGraph` will create `RemoteVariableRef` objects for every variable on the graph, and it will share between the workers information for creating all variables (names as symbols and indices essentially as integers). In an ordinary JuMP model, calling `length(all_variables(m))` for a model `m` may not have noticeable overhead to it if a user only calls this once or twice, but calling `length(all_variables(g))` for a remote graph `g` may be noticeably slower since it is building `RemoteVariableRef`s for all variables on the graph. While this is best practice for both JuMP models and Plasmo `RemoteOptiGraph`s, using `JuMP.num_variables(g)` will be proportionally far more efficient in the case of the `RemoteOptiGraph` than it would be for a JuMP model.

#### 3. Consider defining custom build functions

As noted in 1., lots of macro calls and other function calls can slow down the code for especially large models. One option to avoid this is to build the graph directly on the remote worker inside a remote call or `@spawnat` call. for instance, the user could define a function that takes an `OptiGraph` object and constructs a large optimization problem on it for every worker, such as the following: 

```jldoctest; doctest=false
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

```jldoctest; doctest=false
rgraph = RemoteOptiGraph(worker = 2) # Define a RemoteOptiGraph on worker 2

darray = rgraph.graph # Get the DistributedArray containing the OptiGraph

@spawnat rgraph.worker begin
    lgraph = localpart(darray)[1] # On the remote worker, retrieve the local graph
    build_subgraph_remotely(lgraph) # run the function that was defined on this worker via the @everywhere call
end
```

This will add to the OptiGraph remotely so that there are not large amounts of remote calls. The user can still access the objects on this graph via `all_variables`, `all_nodes`, or by indexing for names. As with an `OptiGraph`, you can access objects by their symbols. For instance, calling `rgraph[:n]` returns a set of `RemoteNodeRef`s that correspond to the `n[1:10]` defined in the `build_subgraph_remotely` function. Similary, we can call `rgraph[:n][1][:x][1]` to get a `RemoteVariableRef` that corresponds to a variable stored on the graph on the remote worker. 
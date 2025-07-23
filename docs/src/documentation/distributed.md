# Plasmo.jl for Distributed Memory

## `RemoteOptiGraph` Overview

In large-scale problems, there can be instances where memory limits optimization or decomposition approaches. In such cases, it can be necessary to distribute the optimization problem to multiple processors. Plasmo.jl has support for placing subgraphs of an optimization problem on separate workers by using the `RemoteOptiGraph` object. At the moment, this is primarily used when applying a decomposition approach where you may want separate subproblems that can be solved on separate workers while still capturing connections (e.g., constraints as edges) between the subproblems. 

The `RemoteOptiGraph` object can be thought of as a wrapper for an `OptiGraph` that is stored on a remote worker. The `RemoteOptiGraph` wrapper "lives" on the primary worker running the Julia REPL while the `OptiGraph` itself is stored on a remote process. The `RemoteOptiGraph` can also have nested subgraphs (just like an `OptiGraph` can contain nested `OptiGraph`s) with each subgraph stored on a worker and can contain `RemoteOptiEdge`s that connect the nested `RemoteOptiGraph`s together (or connect nested `RemoteOptiGraph`s with nodes on the primary `RemoteOptiGraph` with its subgraphs). 

From a user point of view, the `RemoteOptiGraph` functions similarly to an `OptiGraph`. The macros `@variable`, `@constraint`, `@optinode`, and `@objective` work in the same way for a `RemoteOptiGraph` as an `OptiGraph`. These macros, as well as many other JuMP and Plasmo functions have been extended to work with the `RemoteOptiGraph` object. "Lightweight" remote object references are returned by these functions that point to their corresponding objects stored on the `OptiGraph` on the remote worker.

## Introduction to Distributed Programming
Plasmo.jl's distributed functionality is enabled by Distributed.jl and DistributedArrays.jl. While Plasmo.jl's distributed functionality is designed so that the user largely does not have to interact with the commands to access distributed information, the information in this subsection will be helpful in getting started, building performant code, and debugging models. While this subsection provides some basic information needed for effectively building `RemoteOptiGraph`s, further details can be found at [Distributed.jl](https://docs.julialang.org/en/v1/stdlib/Distributed/) and [DistributedArrays.jl](https://juliaparallel.org/DistributedArrays.jl/stable/)'s source code. 

Julia's default is to run code on a main processor or worker. To run distributed code, the user must define additional processors/workers. Distributed.jl refers to the processors in the cluster as `procs` or processors and the remote workers (outside of the main worker on which the REPL is running) as `workers`. Calling `nprocs()` will return the number of processors currently running/accessible while `nworkers()` will return the number of worker processors (typically `nprocs() - 1`). Each processor is referenced by an integer ID. The main processor (on which the Julia REPL is running) is always `1`. To get the set of processor or worker IDs, a user can call `procs` and `workers`. 

To run on additional workers, a user must start additional workers in Julia and define code to run on the workers. Additional workers can be added by calling `addprocs(num_cpus)` where `num_cpus` is an integer value for the number of processors to add or start. Similarly, a user can run `rmprocs` to shutdown and remove one or more Julia processors. Once an additional worker is started, a user must also load required packages (e.g., Plasmo) on the worker they want to use. This can be done via the `@everywhere` macro, which will run the code inside the macro on every worker. For instance, the user can run the following: 

```julia
using Distributed, Plasmo, JuMP

# add three processors
println(nprocs()) # returns 1
addprocs(3)
println(nprocs()) # returns 4

# Plasmo and JuMP are not defined on the remote workers yet until @everywhere is called
@everywhere begin
    using Plasmo
    using JuMP
end
```

To run a task on the distributed worker, a must use functions from Distributed.jl such as `remotecall` or `@spawnat`. As an example, `remotecall` will run a function on a remote worker, such as in the following case: 
```julia
workers = workers()
A = rand(5000)

f = remotecall(maximum, workers[1], A)
```

Here, `remotecall` runs `maximum(A)` on the first worker indexed in the worker pool. Alternatively, a user can use the `@spawnat` macro to run code such as in the following case: 
```julia
f = @spawnat 2 begin
    A = rand(5000)
    maximum(A)
end
```
In this latter example, the matrix `A` is never defined on the main worker and is not accessible in the main Julia REPL because the code was run only on the remote worker. In both cases above, `f` is a `Future` object, meaning it is a reference to the task performed on the worker. Note that a user might expect this to return a Float value (the maximum value in the random vector), but the `Future` object is just a reference to what has been done on the remote worker. To get the value of the `Future` object, a user must "fetch" the value from the worker by calling `fetch(f)`, which will return the expected Float value. 


### Cautions with Distributed Programming
While distributed programming can be useful and accelerate task performance on some problems, there are tradeoffs. Variables, functions, or other allocated memory defined on the main processor are not shared directly with the remote workers. Thus at least two places a user may lose performance in their code is 1) making many calls to the remote worker (e.g., many `fetch` or `@spawnat` calls) and 2) passing large datastructures between the main and remote processors. A user must therefore be careful about both of these tasks. 

#### Limiting calls to the remote
As an example of the first challenge, the second function below will more efficient than the first because there is only one `remotecall` to the worker and only one `fetch` call. 
```julia
A = rand(100, 100)
function do_remote_task_v1(A::Matrix, worker_id::Int)
    max_values = zeros(100)
    for i in 1:100
        row = A[i, :]
        f = @spawnat worker_id begin
            maximum(row)
        end
        max_values[i] = fetch(f)
    end
    return max_values
end

function do_remote_task_v2(A::Matrix, worker_id::Int)
    f = @spawnat worker_id begin
        max_values = zeros(100)
        for i in 1:100
            row = A[i, :]
            max_values[i] = maximum(row)
        end
        max_values
    end
    return fetch(f)
end
```

In terms of Plasmo.jl performance, it can be helpful to define constructor functions for graphs that are being built on remote workers. Building large graphs from many different `@variable` or `@constraint` calls on the main processor will work but can be slower than running these directly on the remote worker. This is discussed in more detail in the Quickstart on distributed Plasmo.jl. 

#### Limiting memory sent to the remote

Memory form the main worker is shared to the remote worker inside of `remotecall` or `@spawnat`, and the user must be careful in what information is shared in these remote calls. For instance, in the following case, the entire `A` matrix is being shared to the remote worker since it is explicitly referenced inside the `@spawnat` call even though only one entry of the `A` matrix is necessary. 
```julia
A = rand(100, 100)
f = @spawnat workers[1] begin
    A[1, 1] ** 2
end
fetch(f)
```
A more efficient option in terms of how much memory is shared, the user can create a reference/variable for this single entry outside of the fetch call, such as the following: 
```julia
A = rand(100, 100)
first_entry = A[1,1]
f = @spawnat workers[1] begin
    first_entry ** 2
end
fetch(f)
```
In the case of Plasmo.jl (or JuMP.jl for that matter), sharing pieces of a traditional optimization problem across workers can include the entire optimization problem. For instance, because each `Plasmo.NodeVariableRef` includes a reference to a node and each node includes a reference to a graph, passing a `Plasmo.NodeVariableRef` shares the entire OptiGraph between workers. This was a major motivation for the `RemoteOptiGraph` abstraction, which has been implemented such that only the required data (e.g., the `MOI.VariableIndex`) is passed between workers and does not include a reference to the full graph. 

## Data Structure

Plasmo.jl's distributed implementation is built on the `RemoteOptiGraph` data object. This object includes a `worker` field, which is the remote worker on which the actual `OptiGraph` is stored. The `graph` field is a length 1 `DArray` (a distributed array). The `DArray` is a light "wrapper" of sorts that stores the actual `OptiGraph` on the remote worker. `RemoteOptiGraph`s can also be nested in other `RemoteOptiGraphs` just as `OptiGraph`s can be, so there are also fields called `parent_graph` and `subgraphs`. Finally, there are fields `optiedges`, `element_data`, `obj_data`, `label`, and `ext`. 

Several reference types and objects have been defined for working with the distributed implementation. The `RemoteOptiGraph` object lives on the main worker and is essentially a wrapper and pointer to an `OptiGraph` on the remote worker. Nodes, edges, and variables from the `OptiGraph` on the remote worker can be referenced on the main worker via the structs `RemoteNodeRef`, `RemoteEdgeRef`, and `RemoteVariableRef`. Each of these objects belongs to the `RemoteOptiGraph` but includes information that points to the objects on the remote worker. In this way, the functions for working with Plasmo.jl's `OptiGraph` object have been extended for working with these remote reference objects. For instance, calling `@optinode` and passing a `RemoteOptiGraph` object will add the node to the `OptiGraph` on the remote worker and return a `RemoteNodeRef` to the main worker that represents the actual node added on the remote worker. Similarly, passing a `RemoteNodeRef` to the `@variable` constructs variables on the remote worker's `OptiGraph` but returns `RemoteVariableRef` objects on the main worker. Examples of many of these functions are included in the Quickstart

The other important data structure is the `RemoteOptiEdge`. This object captures constraints between multiple `RemoteOptiGraph`s. Since `RemoteOptiGraph`s can capture nested structures, constraints between these structures are stored on the `RemoteOptiEdge`. These constraints are stored directly on the `RemoteOptiGraph` object. In this way, the `RmeoteOptiEdge` structure is different than the `RemoteEdgeRef`, since the latter represents an edges contained in the `OptiGraph` object stored on the remote worker.

Finally, we note on these `RemoteOptiGraph` objects are likely most useful for decomposition approaches or situations where there are memory limiations. Unlike the `OptiGraph` abstraction, calling `JuMP.optimize!` on a `RemoteOptiGraph` only optimizes the `OptiGraph` that is stored remotely on the `RemoteOptiGraph` and does NOT consider subgraphs. When optimizing an `OptiGraph`, calling `JuMP.optimize!` will include all subgraphs in the optimization problem, but this is not the case of the remote. 

## Decomposition Schemes for Working with `RemoteOptiGraph`s

The package PlasmoBenders.jl has been designed to work with both Plasmo.jl's `OptiGraph`s and `RemoteOptiGraph`s. This package implements Benders decomposition and is available [here](https://github.com/plasmo-dev/PlasmoAlgorithms.jl/tree/main/lib/PlasmoBenders). Using the `RemoteOptiGraph`s with PlasmoBenders.jl requires PlasmoBenders v0.2.0+.
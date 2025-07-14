# Plasmo.jl for Distributed Memory

In large-scale problems, there can be instances where memory limits optimization or decomposition approaches. In such cases, it can be necessary to distribute the optimization problem to multiple processors. Plasmo.jl has support for placing subgraphs of an optimization problem on separate workers by using the `RemoteOptiGraph` object. At the moment, this is primarily useful when applying a decomposition approach where you may want separate subproblems that can be solved on separate workers while still capturing connections (e.g., constraints as edges) between the subproblems. 

The `RemoteOptiGraph` object can be thought of as a wrapper for an `OptiGraph` that is stored on a remote worker. The `RemoteOptiGraph` wrapper "lives" on the primary worker running the Julia REPL while the `OptiGraph` itself is stored on a remote process. The `RemoteOptiGraph` can also have nested subgraphs (just like an `OptiGraph` can contain nested `OptiGraph`s) and can contain `RemoteOptiEdge`s that connect the nested `RemoteOptiGraph`s together (or connect nested `RemoteOptiGraph`s with nodes on the primary `RemoteOptiGraph` with its subgraphs). 

From a user point of view, the `RemoteOptiGraph` functions similarly to an `OptiGraph`. The macros `@variable`, `@constraint`, `@optinode`, and `@objective` work in the same way for a `RemoteOptiGraph` as an `OptiGraph`. These macros, as well as many other JuMP and Plasmo functions have been extended to work with the `RemoteOptiGraph` object. "Lightweight" remote object references are returned by these functions that point to their corresponding objects stored on the `OptiGraph` on the remote worker.

Plasmo.jl's distributed functionality is designed so that the user largely does not have to interact with the commands to access distributed information. The distributed framework is enabled via Distributed.jl and DistributedArrays.jl. 

Note on distributed programming

Motivation for distributed memory

How it works in Plasmo and extended code

Overview on distributed programming in Julia - maybe link to Distributed.jl and DistributedArrays.jl

## Data Structure

RemoteOptiGraph

RemoteNodeRef, RemoteVariableRef, RemoteEdgeRef, 

RemoteOptiEdge

## Example Code

## Note on Algorithms for working with it

link to PlasmoBenders and PlasmoBenders code
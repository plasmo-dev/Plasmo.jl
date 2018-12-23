# BasePlasmoGraph

A BasePlasmoGraph wraps a LightGraphs.jl AbstractGraph and adds additional attributes for managing subgraphs and data.
These are all of the graph functions a user might use in Plasmo.  Most core functions from LightGraphs.jl have been extended for a PlasmoGraph.

## Graph Functions

```@docs
BasePlasmoGraph
getindex(::BasePlasmoGraph)
getindex(::BasePlasmoGraph,::BasePlasmoNode)
```

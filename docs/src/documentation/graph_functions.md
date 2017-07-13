# The Plasmo Graph

A PlasmoGraph wraps a LightGraphs.jl Graph (or DiGraph) and adds additional attributes for managing subgraphs and models.
These are all of the graph functions a user might use in plasmo.  Most core functions from LightGraphs.jl have been dispatched.

## Graph Functions

```@docs
PlasmoGraph

getindex(::PlasmoGraph)
getindex(::PlasmoGraph,::NodeOrEdge)
getindex(::NodeOrEdge)
```

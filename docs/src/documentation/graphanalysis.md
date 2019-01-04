# ModelGraph Analysis

A `ModelGraph` supports graph analysis functions such as graph partitioning or community detection.  The graph analysis functions are particularly
useful for creating decompositions of optimization problems and in fact, this is what is done to use Plasmo's built-in structure-based solvers.

## Methods

```@docs
Metis.partition(graph::ModelGraph,n_parts::Int64)
LightGraphs.label_propagation(graph::ModelGraph)
```
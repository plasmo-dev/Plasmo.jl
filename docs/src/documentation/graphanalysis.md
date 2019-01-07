# ModelGraph Analysis

A `ModelGraph` supports graph analysis functions such as graph partitioning or community detection.  The graph analysis functions are particularly
useful for creating decompositions of optimization problems and in fact, this is what is done to use Plasmo's built-in structure-based solvers.

## Partitioning

Graph partitioning can be performed on a `ModelGraph` using `Metis.partition`.  The function requires a working Metis interface, which can be cloned with:

```julia
using Pkg
Pkg.clone("https://github.com/jalving/Metis.jl.git")
```  
Once Metis is installed, graph partitions can be obtained like following:

```julia
using Metis
#Assuming we have a ModelGraph
partitions = Metis.partition(graph,4,alg = :KWAY)  #Use the Metis KWAY partition
```
where `partitions` will be a vector of vectors.  Each vector will contain the indices of the nodes in `graph`.  Partitions can be used
to communicate structure to `PlasmoSolvers` or the `PipsSolver` if `PlasmoSolverInterface` is installed.

## Methods

```@docs
Metis.partition(graph::ModelGraph,n_parts::Int64)
LightGraphs.label_propagation(graph::ModelGraph)
```

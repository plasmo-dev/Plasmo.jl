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

## Community Detection

Graph community detection algorithms can also be used to generate graph partitions, although they do not necessarily return partitions of a selected size.  
The current supported community detection algorithms are as follows:

### Label propagation
```julia
using LightGraphs
communities = LightGraphs.label_propagation(graph)
```

### Bethe Hessian
```julia
using CommunityDetection
communities = CommunityDetection.community_detection_bethe(graph)
```

### Louvain Fast Unfolding Algorithm
For now, you will need to clone a forked version of the CommunityDetection.jl package to use the fast unfolding algorithm.

```julia
using Pkg
Pkg.clone("https://github.com/jalving/CommunityDetection.jl.git")
using CommunityDetection
communities = CommunityDetection.community_detection_louvain(graph)
```



## Methods

```@docs
Metis.partition(graph::ModelGraph,n_parts::Int64)
LightGraphs.label_propagation(graph::ModelGraph)
CommunityDetection.community_detection_nback
CommunityDetection.community_detection_bethe
CommunityDetection.community_detection_louvain
```

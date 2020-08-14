# Partitioning
One of the key aspects behind modeling with optigraphs is that they effectively allow for the unraveling of
structure in optimization problems.  This unraveled structure can exploit popular graph partitioning approaches such as those used in [Metis](https://github.com/JuliaSparse/Metis.jl) or [KaHyPar](https://github.com/kahypar/KaHyPar.jl).

## OptiGraph Representations
To partition an optigraph, we first need to cast it into a graph representation that reflects the partitioning algorithm. There are numerous graph representations that
can be used to express the topology and connectivity of optimization problems.  By default, we assume that an optigraph adheres to a hypergraph
representation where optinodes represent hypernodes and optiedges correspond to hyperedges that connect two or more optinodes.

To help demonstrate partitioning capabilities, we instantiate the optimization problem in the below code snippet:

```julia
using Plasmo

T = 100          #number of time points
d = sin.(1:T)    #disturbance vector

graph = OptiGraph()
@optinode(graph,state[1:T])
@optinode(graph,control[1:T-1])

for node in state
    @variable(node,x)
    @constraint(node, x >= 0)
    @objective(node,Min,x^2)
end
for node in control
    @variable(node,u)
    @constraint(node, u >= -1000)
    @objective(node,Min,u^2)
end

@linkconstraint(graph,[i = 1:T-1],state[i+1][:x] == state[i][:x] + control[i][:u] + d[i])
n1 = state[1]
@constraint(n1,n1[:x] == 0)
```


## Partitioning Interface

## Methods

```@docs
Partition
make_subgraphs!
```

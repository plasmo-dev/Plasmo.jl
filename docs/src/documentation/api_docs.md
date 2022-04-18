# API Documentation

## OptiGraph Functions
```@docs
OptiGraph
add_node!
getnode
getnodes
optinodes
all_node
all_nodes
all_optinodes
add_subgraph!
subgraphs
all_subgraphs
linkconstraints
all_linkconstraints
```

## OptiNode Functions
```@docs
set_model
getedge
getedges
optiedges
all_edge
all_edges
all_optiedges
is_node_variable
```

## OptiEdge Functions
```@docs
OptiEdge
LinkConstraint
```

## Base
```@docs
Base.getindex(::OptiGraph,::OptiNode)
Base.getindex(::OptiGraph,::OptiEdge)
```

## Macros
```@docs
@optinode
@linkconstraint
```

## Extended JuMP Functions
```@docs
JuMP.all_variables(::OptiNode)
JuMP.set_optimizer(::OptiGraph,::Any)
JuMP.objective_function(::OptiGraph)
JuMP.value
JuMP.num_variables(::OptiGraph)
JuMP.num_constraints(::OptiGraph)
```

## Partitioning and Aggregation

```@docs
Partition
apply_partition!
aggregate
aggregate!
expand
Plasmo.neighborhood
HyperGraph
gethypergraph
```

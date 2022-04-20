# API Documentation

## OptiGraph
```@docs
OptiGraph
optigraph_reference
add_subgraph!
getsubgraph
all_subgraph
getsubgraphs
all_subgraphs
num_subgraphs
num_all_subgraphs
has_subgraphs
add_node!
getnode
getnodes
optinodes
all_node
all_nodes
all_optinodes
Plasmo.add_optiedge!
Plasmo.add_edge!
getedge
getedges
optiedges
all_edge
all_edges
all_optiedges
linkconstraints
all_linkconstraints
Base.getindex(::OptiGraph, ::OptiNode)
Base.getindex(::OptiGraph, ::OptiEdge)
```

## OptiNode Functions
```@docs
set_model
is_node_variable
```

## OptiEdge Functions
```@docs
OptiEdge
LinkConstraint
```

## Macros
```@docs
@optinode
@linkconstraint
```

## Extended Functions
```@docs

JuMP.all_variables(::OptiNode)
JuMP.set_optimizer(::OptiGraph,::Any)
JuMP.objective_function(::OptiGraph)
JuMP.value
JuMP.num_variables(::OptiGraph)
JuMP.num_constraints(::OptiGraph)
```

## Graph Processing and Partitioning

```@docs
Partition
apply_partition!
aggregate
aggregate!
expand
Plasmo.neighborhood
hyper_graph
```

## Plotting
```@docs
    PlasmoPlots.layout_plot
    PlasmoPlots.matrix_plot
```

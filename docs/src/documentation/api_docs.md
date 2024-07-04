# API Documentation

## OptiGraph Methods
```@docs
OptiGraph
OptiNode
OptiEdge
@optinode
@linkconstraint
@nodevariables
graph_backend
graph_index
source_graph
add_subgraph
local_subgraphs
all_subgraphs
num_local_subgraphs
num_subgraphs
add_node
get_node
local_nodes
all_nodes
collect_nodes
num_local_nodes
num_nodes
add_edge
get_edge
local_edges
all_edges
num_local_edges
num_edges
num_local_link_constraints
num_linkconstraints
local_link_constraints
all_link_constraints
Base.getindex(::OptiGraph, ::Int)
```

## JuMP Interop Methods
```@docs
set_jump_model
```

## Extended Methods
```@docs
JuMP.all_variables
JuMP.set_optimizer
JuMP.optimize!
JuMP.objective_function
JuMP.value
JuMP.dual
JuMP.num_variables
JuMP.num_constraints
JuMP.object_dictionary
JuMP.add_variable
JuMP.add_constraint
JuMP.list_of_constraint_types
JuMP.all_constraints
JuMP.objective_value
JuMP.objective_sense
JuMP.set_objective
JuMP.set_objective_function
JuMP.set_objective_sense
JuMP.termination_status
JuMP.constraint_ref_with_index
```

## Graph Projections
```@docs
hyper_projection
clique_projection
edge_projection
edge_clique_projection
edge_hyper_projection
bipartite_projection
```

## Partitioning and Aggregation
```@docs
Partition
assemble_optigraph
apply_partition!
aggregate
```

## Graph Topology
```@docs
Graphs.all_neighbors
Graphs.induced_subgraph
Graphs.neighborhood
incident_edges
induced_edges
identify_edges
identify_nodes
expand
```

## Plotting
```@docs
PlasmoPlots.layout_plot
PlasmoPlots.matrix_plot
```

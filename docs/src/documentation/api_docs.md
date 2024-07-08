# API Documentation

## OptiGraph Methods
```@docs
OptiGraph
OptiNode
OptiEdge
@optinode
@linkconstraint
@nodevariables
set_to_node_objectives
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
num_local_variables
add_edge
get_edge
get_edge_by_index
Plasmo.has_edge
local_edges
all_edges
num_local_edges
num_edges
num_local_link_constraints
num_link_constraints
local_link_constraints
all_link_constraints
num_local_constraints
local_constraints
local_elements
all_elements
Base.getindex(::OptiGraph, ::Int)
```

## JuMP.jl Extended Methods
```@docs
JuMP.name
JuMP.set_name
JuMP.index
JuMP.backend
JuMP.value
JuMP.add_variable
JuMP.num_variables
JuMP.all_variables
JuMP.start_value
JuMP.set_start_value
JuMP.add_constraint
JuMP.list_of_constraint_types
JuMP.num_constraints
JuMP.all_constraints
JuMP.objective_value
JuMP.dual_objective_value
JuMP.objective_sense
JuMP.objective_function
JuMP.objective_function_type
JuMP.objective_bound
JuMP.set_objective
JuMP.set_objective_function
JuMP.set_objective_sense
JuMP.set_objective_coefficient
JuMP.set_optimizer
JuMP.add_nonlinear_operator
JuMP.optimize!
JuMP.termination_status
JuMP.primal_status
JuMP.dual_status
JuMP.relative_gap
JuMP.constraint_ref_with_index
JuMP.object_dictionary
```

## Interop with JuMP.jl
```@docs
set_jump_model
```

## Graph Projections
```@docs
Plasmo.GraphProjection
hyper_projection
edge_hyper_projection
clique_projection
edge_clique_projection
bipartite_projection
```

## Partitioning and Aggregation
```@docs
Partition
assemble_optigraph
apply_partition!
aggregate
aggregate_to_depth
aggregate_to_depth!
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

<!--  ```@docs
PlasmoPlots.layout_plot
PlasmoPlots.matrix_plot
``` -->
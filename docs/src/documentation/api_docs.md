# API Documentation

## OptiGraph
```@docs
OptiGraph
@optinode
@linkconstraint
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
num_linkconstraints
has_objective
has_nl_objective
Base.getindex(::OptiGraph, ::OptiNode)
Base.getindex(::OptiGraph, ::OptiEdge)
```

## OptiNode
```@docs
OptiNode
jump_model
set_model
getlabel
set_label
is_node_variable
is_set_to_node
Base.getindex(node::OptiNode, symbol::Symbol)
Base.setindex(node::OptiNode, value::Any, symbol::Symbol)
num_linked_variables
```

## OptiEdge
```@docs
OptiEdge
LinkConstraint
LinkConstraintRef
attached_node
set_attached_node
```


## Extended Functions
```@docs
JuMP.all_variables
JuMP.set_optimizer
JuMP.objective_function
JuMP.value
JuMP.dual
JuMP.num_variables
JuMP.num_constraints
JuMP.object_dictionary
JuMP.add_variable
JuMP.add_constraint
JuMP.add_nonlinear_constraint
JuMP.num_nonlinear_constraints
JuMP.list_of_constraint_types
JuMP.all_constraints
JuMP.objective_value
JuMP.objective_sense
JuMP.set_objective
JuMP.set_nonlinear_objective
JuMP.set_objective_function
JuMP.set_objective_sense
JuMP.NLPEvaluator
JuMP.termination_status
```

## Graph Processing and Partitioning

```@docs
hyper_graph
clique_graph
edge_graph
edge_hyper_graph
bipartite_graph
Plasmo.graph_backend
Partition
apply_partition!
aggregate
aggregate!
expand
LightGraphs.all_neighbors
LightGraphs.induced_subgraph
Plasmo.incident_edges
Plasmo.induced_edges
Plasmo.identify_edges
Plasmo.identify_nodes
Plasmo.neighborhood
hierarchical_edges
linking_edges

```

## Plotting
```@docs
PlasmoPlots.layout_plot
PlasmoPlots.matrix_plot
```

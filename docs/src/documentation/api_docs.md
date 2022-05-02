# API Documentation

## OptiGraph
```@docs
OptiGraph
@optinode
@linkconstraint
optigraph_reference
add_subgraph!
subgraph
subgraphs
all_subgraphs
subgraph_by_index
num_subgraphs
num_all_subgraphs
has_subgraphs
add_node!
optinode
optinodes
all_nodes
optinode_by_index
Plasmo.add_optiedge!
optiedge
optiedges
all_edges
optiedge_by_index
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
label
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
JuMP.optimize!
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
Plasmo.graph_backend
Plasmo.HyperGraph
hyper_graph
clique_graph
edge_graph
edge_hyper_graph
bipartite_graph
Partition
apply_partition!
aggregate
aggregate!
all_neighbors
induced_subgraph
Plasmo.incident_edges
Plasmo.induced_edges
Plasmo.identify_edges
Plasmo.identify_nodes
Plasmo.neighborhood
expand
hierarchical_edges
linking_edges
```

## Plotting
```@docs
PlasmoPlots.layout_plot
PlasmoPlots.matrix_plot
```

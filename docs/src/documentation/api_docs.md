# Methods

## OptiGraph Functions
```@docs
OptiGraph
@optinode
OptiNode
add_node!
getnode
getnodes
find_node
is_node_variable
Base.getindex(::OptiGraph,::OptiNode)
Base.getindex(::OptiGraph,::OptiEdge)
all_nodes
set_model
@linkconstraint
OptiEdge
getedge
getedges
all_edges
LinkConstraint
getlinkconstraints
all_linkconstraints
add_subgraph!
getsubgraphs
all_subgraphs
```

## Extended JuMP Functions
```@docs
JuMP.all_variables(::OptiNode)
JuMP.set_optimizer(::OptiGraph,::Any)
JuMP.objective_function(::OptiGraph)
JuMP.value(::OptiNode,::VariableRef)
JuMP.num_variables(::OptiGraph)
JuMP.num_constraints(::OptiGraph)
JuMP.value
```

## Plotting
PlasmoPlots.jl extends methods from the [Plots.jl](https://github.com/JuliaPlots/Plots.jl) Julia package to create graph layout visuals.
```@docs
    PlasmoPlots.layout_plot(::OptiGraph)
    PlasmoPlots.matrix_plot(::OptiGraph)
```

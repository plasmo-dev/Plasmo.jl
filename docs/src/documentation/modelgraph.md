# ModelGraph

## Constructor
The `ModelGraph` is the primary object for creating graph-based models in Plasmo.jl.  A `ModelGraph` extends the `JuMP.AbstractModel` and offers a collection of `ModelNode`s (which also
extend `JuMP.AbstractModel`) which represent solvable optimization problems.
`ModelNode`s are connected by `LinkConstraint`s over variables which induce underlying `LinkEdge`s.  s

A `ModelGraph` does not require any arguments to construct:

```julia
mg = ModelGraph()
```

A `ModelGraph` optimizer can be specified in the same way as in JuMP using `set_optimizer(::ModelGraph)`.  An optimizer can be any
JuMP compatible solver or a custom Plasmo.jl provided solver (see the solvers section).  
For example, we could construct a `ModelGraph` that uses the `IpoptSolver` from the Ipopt package:

```julia
graph = ModelGraph()
ipopt = Ipopt.Optimizer
set_optimizer(graph,ipopt)
```

## Adding Nodes
`ModelNode`s can be added to a `ModelGraph` using the `@node` macro.  For instance, the below piece of code add the node `n1` to the modelgraph `mg`
```julia
@node(mg,n1)
```

It is also possible to create sets of `ModelNode`s in a single call to `@node` like shown in the below code snippet.
This example creates a 2x2 grid of modelnodes.

```julia
@node(mg,nodes[1:2,1:2])
for node in nodes
    @variable(node,x>=0)
end
```
We can iterate over the nodes in a `ModelGraph` using the `getnodes` function.  For example

```julia
for node in getnodes(mg)
    println(node)
end
```
will print the string for every node in the `ModelGraph` graph.  


Variables within a `ModelNode` can be accessed directly from their enclosing node.  
```julia
@variable(n1,x >= 0)
println(n1[:x])    #accesses variable x on jump_model
```

## Adding LinkConstraints

`LinkConstraint`s are linear constraints that couple variables across different `ModelNode`s.  The simplest way to add `LinkConstraint`s
is to use the `@linkconstraint` macro.  This macro accepts the same input as a JuMP `@constraint` macro and creates linear constraints over multiple nodes within the same graph.

```julia
@variable(nodes[1,1],x >= 0)

@linkconstraint(graph,n1[:x] == nodes[1,1][:x])  #creates a linear constraint between nodes n1 and n2
```


## Subgraph Structures

It is possible to create subgraphs within a `ModelGraph` object.  This is helpful when a user wants to develop to separate systems and link them together within
a higher level graph.

```julia
sg1 = ModelGraph()
@node(sg1,nsubs1[1:2])
for node in nsub
    @variable(node,y[1:2] >= 0 )
end
@linkconstraint(sg1,nsubs1[:y][1] == nsubs1[:y][2])  #creates a linear constraint between nodes n1 and n2

sg2 = ModelGraph()
@node(sg2,nsubs2[1:2])
for node in nsub
    @variable(node,y[1:2] >= 0 )
end
@linkconstraint(sg2,nsubs2[:y][1] == nsubs2[:y][2])  #creates a linear constraint between nodes n1 and n2

add_subgraph!(mg,sg1)
add_subgraph!(mg,sg2)

@linkconstraint(mg,nsubs1[:y][2]) == nsubs2[:y][2])
```

## Methods

### ModelGraph
The `ModelGraph` contains the following useful methods:

```@docs
Plasmo.ModelGraph
Plasmo.objective_value
set_optimizer(mg::ModelGraph,optimizer::JuMP.OptimizerFactory)
```
### ModelNode
`ModelNode`s contain methods for managing their contained JuMP models.

```@docs
Plasmo..ModelNode
Plasmo.add_node!(graph::AbstractModelGraph,model::JuMP.AbstractModel)
```

### LinkConstraints
```@docs
Plasmo.getlinkconstraints
Plasmo.all_linkconstraints

```

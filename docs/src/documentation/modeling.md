# Modeling
In Plasmo.jl, the primary modeling object is called an `OptiGraph`. The `OptiGraph` extends the `JuMP.AbstractModel` abstract type to facilitate a modular graph-based modeling style
 and provides and is composed of `OptiNodes` (which also
extend `JuMP.AbstractModel`) which represent modular optimization problems.
`OptiNodes` are connected by `OptiEdges` which encapsulate `LinkConstraints`.

## Creating an OptiGraph
An `OptiGraph` does not require any arguments to construct:

```julia
optigraph = OptiGraph()
```
An `OptiGraph` optimizer can be specified in the same way as in JuMP using `set_optimizer(::OptiGraph)`.  An optimizer can be any
JuMP compatible solver or a custom Plasmo.jl provided solver (see the solvers section).  
For example, we could construct an `OptiGraph` that uses `Ipopt.Opimizer` from the Ipopt package:

```julia
graph = OptiGraph()
ipopt = Ipopt.Optimizer
set_optimizer(graph,ipopt)
```

## Adding OptiNodes
`OptiNode`s can be added to a `OptiGraph` using the `@optinode` macro.  For instance, the below piece of code add the node `n1` to the OptiGraph `mg`
```julia
@optinode(mg,n1)
```

It is also possible to create sets of `OptiNode`s in a single call to `@optinode` like shown in the below code snippet.
This example creates a 2x2 grid of `OptiNode`s.

```julia
@optinode(mg,nodes[1:2,1:2])
for node in nodes
    @variable(node,x>=0)
end
```
We can iterate over the nodes in a `OptiGraph` using the `getnodes` function.  For example

```julia
for node in getnodes(mg)
    println(node)
end
```
will print summary information for every node in `optigraph`.  


Variables within a `OptiNode` can be accessed directly from their enclosing node.  
```julia
@variable(n1,x >= 0)
println(n1[:x])    #accesses variable x on jump_model
```

## Adding LinkConstraints (OptiEdges)

`LinkConstraints` are linear constraints that couple variables across different `OptiNode`s.  The simplest way to add `LinkConstraint`s
is to use the `@linkconstraint` macro.  This macro accepts the same input as a JuMP `@constraint` macro and creates linear constraints over multiple nodes within the same graph.

```julia
@variable(nodes[1,1],x >= 0)

@linkconstraint(graph,n1[:x] == nodes[1,1][:x])  #creates a linear constraint between nodes n1 and n2
```


## Hierarchical Modeling with Subgraphs

It is possible to create subgraphs within a `OptiGraph` object.  This is helpful when a user wants to develop to separate systems and link them together within
a higher level graph.

```julia
sg1 = OptiGraph()
@optinode(sg1,nsubs1[1:2])
for node in nsub
    @variable(node,y[1:2] >= 0 )
end
@linkconstraint(sg1,nsubs1[:y][1] == nsubs1[:y][2])  #creates a linear constraint between nodes n1 and n2

sg2 = OptiGraph()
@optinode(sg2,nsubs2[1:2])
for node in nsub
    @variable(node,y[1:2] >= 0 )
end
@linkconstraint(sg2,nsubs2[:y][1] == nsubs2[:y][2])  #creates a linear constraint between nodes n1 and n2

add_subgraph!(mg,sg1)
add_subgraph!(mg,sg2)

@linkconstraint(mg,nsubs1[:y][2]) == nsubs2[:y][2])
```

## Methods
Modeling with an `OptiGraph` encompasses the following useful methods:

### OptiGraph
```@docs
Plasmo.OptiGraph
Plasmo.getnodes
Plasmo.all_nodes
```
### OptiNode
`OptiNode`s contain methods for managing their contained JuMP models.

```@docs
Plasmo.OptiNode
Plasmo.@optinode(graph::OptiGraph,expr::Expr)
```

###OptiEdge

### Attributes
```@docs

Plasmo.getlinkconstraints
Plasmo.all_linkconstraints
```

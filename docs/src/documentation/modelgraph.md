# ModelGraph

## Constructor
The `ModelGraph` is the primary object for creating graph-based models in Plasmo.jl.  A `ModelGraph` is a collection of `ModelNode`s
which are connected by `LinkConstraint`s (i.e. edges) over variables.  One way to think of the structure of a `ModelGraph` is a HyperGraph wherein edges represent linking constraints
that can link multiple `ModelNode` variables.

A `ModelGraph` does not require any arguments to construct:

```julia
mg = ModelGraph()
```

A `ModelGraph` solver can be specified upon construction using the `solver` keyword argument.  A `solver` can be any JuMP compatible solver or a Plasmo.jl provided solver (see solvers section).  
For example, we could construct a
`ModelGraph` that uses the `IpoptSolver` from the Ipopt package:

```julia
graph = ModelGraph(solver = IpoptSolver())
```

## Adding Nodes
Nodes can be added to a `ModelGraph` using the `add_node!` function.  By default, a node contains an empty JuMP `Model` object.

```julia
n1 = add_node!(graph)
```

A model can be set upon creation by providing a second argument.  For example:

```julia
model = JuMP.Model()
n1 = add_node!(graph,model)  #sets model to n1
```
where `model` is a JuMP `Model` object.  We can also set a model on a node after construction:

```julia
setmodel(n1,model)
```
This can be helpful in instances where a user wants to swap out a model on a node without changing the graph topology.  Keep in mind however that swapping out
a model will by default remove any link-constraints that involve that node.  Also note that any single JuMP `Model` can only be assigned to a single node.

We can also iterate over the nodes in a `ModelGraph` using the `getnodes` function.  For example

```julia
for node in getnodes(graph)
    println(node)
end
```
will print the string for every node in the `ModelGraph` graph.  

`ModelNode`s can also be retrieved based on their index within a `ModelGraph` or vic versa.  
For example, since n1 was the first node added to mg, it will have an index of 1.

```julia
n1 == getnode(mg,1)   #will return true
getindex(graph,n1) == 1  #will also return true
```

Variables within a JuMP `Model` can be accessed directly from their enclosing node.  

```julia
jump_model = Model()
@variable(jump_model,x >= 0)
setmodel(n1,jump_model)
println(n1[:x])    #accesses variable x on jump_model
```

## Adding LinkConstraints

`LinkConstraint`s are linear constraints that couple variables across different `ModelNode`s.  The simplest way to add `LinkConstraint`s
is to use the `@linkconstraint` macro.  This macro accepts the same input as a JuMP `@constraint` macro and creates linear constraints over multiple nodes within the same graph.

```julia
jump_2 = Model()
@variable(jump_2,x >= 0)
n2 = add_node!(graph,jump_2)

@linkconstraint(graph,n1[:x] == n2[:x])  #creates a linear constraint between nodes n1 and n2
```


## Subgraph Structures

It is possible to create subgraphs within a `ModelGraph` object.  This is helpful when a user wants to develop to separate systems and link them together within
a higher level graph.

(Section TBD)


## Methods

### ModelGraph
The `ModelGraph` contains the following useful methods:

```@docs
Plasmo.PlasmoModelGraph.ModelGraph
Plasmo.PlasmoModelGraph.getobjectivevalue
Plasmo.PlasmoModelGraph.getinternaljumpmodel
setsolver(model::AbstractModelGraph,solver::MathProgBase.AbstractMathProgSolver)
setsolver(model::AbstractModelGraph,solver::AbstractPlasmoSolver)
Plasmo.PlasmoModelGraph.getsolver
```
### ModelNode
`ModelNode`s contain methods for managing their contained JuMP models.

```@docs
Plasmo.PlasmoModelGraph.ModelNode
Plasmo.PlasmoModelGraph.add_node!(graph::AbstractModelGraph,model::JuMP.AbstractModel)
Plasmo.PlasmoModelGraph.setmodel(node::ModelNode,model::JuMP.AbstractModel)
Plasmo.PlasmoModelGraph.is_nodevar
Plasmo.PlasmoModelGraph.getnode(model::JuMP.AbstractModel)
Plasmo.PlasmoModelGraph.getnode(var::JuMP.AbstractJuMPScalar)
```

### LinkConstraints
```@docs
Plasmo.PlasmoModelGraph.getlinkconstraints(graph::AbstractModelGraph)
Plasmo.PlasmoModelGraph.getsimplelinkconstraints
Plasmo.PlasmoModelGraph.gethyperlinkconstraints
Plasmo.PlasmoModelGraph.get_all_linkconstraints
Plasmo.PlasmoModelGraph.addlinkconstraint
Plasmo.PlasmoModelGraph.getlinkconstraints(graph::AbstractModelGraph,node::ModelNode)
Plasmo.PlasmoModelGraph.getlinkconstraints(node::ModelNode)

```

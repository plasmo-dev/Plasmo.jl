# ModelGraph

## Constructor
The `ModelGraph` is the primary object for creating graph-based models in Plasmo.jl.  A `ModelGraph` is a collection of `ModelNode`s
which are connected by means of `LinkingEdge`s (link constraints) over variables.  One way to think of the structure of a `ModelGraph` is a HyperGraph wherein edges represent linking constraints
that can link multiple `ModelNode` variables.

A `ModelGraph` does not require any arguments to construct:

```julia
mg = ModelGraph()
```

A `ModelGraph` solver can be specified upon construction using the `solver` keyword argument.  A `solver` can be any JuMP compatible solver or a Plasmo provided solver (see solvers section).  
For example, we could construct a
`ModelGraph` that starts with the `IpoptSolver` from the Ipopt package:

```julia
mg = ModelGraph(solver = IpoptSolver())
```

## Adding Model Nodes
Nodes can be added to a `ModelGraph` using the `add_node!` function.  By default, a node contains an empty JuMP `Model` object.

```julia
n1 = add_node!(mg)
```

A model can be set upon creation by providing a second argument.  For example:

```julia
model = JuMP.Model()
n1 = add_node!(mg,model)
```
where `model` is a JuMP `Model` object.  We can also set a model on a node after construction:

```julia
setmodel(n1,model)
```
This can be helpful in instances where a user wants to swap out a model on a node without changing the graph topology.  Keep in mind however that swapping out
a model will remove any link constraints that involve that node.

We can also iterate over the nodes in a `ModelGraph` using `getnodes`.

## Adding Link Constraints

Link constraints are linear constraints that couple variables across different `ModelNode`s.


## Methods
The `ModelGraph` contains the following useful methods:

```@docs
Plasmo.PlasmoModelGraph.ModelGraph
Plasmo.PlasmoModelGraph.getobjectivevalue
Plasmo.PlasmoModelGraph.getinternaljumpmodel
Plasmo.PlasmoModelGraph.setsolver
Plasmo.PlasmoModelGraph.getsolver
Plasmo.PlasmoModelGraph.addlinkconstraint
Plasmo.PlasmoModelGraph.getlinkconstraints
Plasmo.PlasmoModelGraph.getsimplelinkconstraints
Plasmo.PlasmoModelGraph.gethyperlinkconstraints
Plasmo.PlasmoModelGraph.get_all_linkconstraints
```

`ModelNode`s contain methods for managing their contained JuMP models.

```@docs
Plasmo.PlasmoModelGraph.ModelNode
```

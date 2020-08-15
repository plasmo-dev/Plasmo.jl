# Modeling
In Plasmo.jl, the primary modeling object is called an [`OptiGraph`](@ref). The `OptiGraph` extends the `JuMP.AbstractModel` type from `JuMP` and permits a graph-based modeling style (where a graph is a
collection of nodes connected by edges). This graph-based approach uses ideas such as modularity and hierarchical modeling to express complex optimization problems and to reveal inherent structures that lend themselves to
graph analysis tasks such as partitioning. The `OptiGraph` represents the following optimization problem.

```math
\begin{aligned}
    \min_{{\{x_n}\}_{n \in \mathcal{N}(\mathcal{G})}} & \quad \sum_{n \in \mathcal{N(\mathcal{G})}} f_n(x_n) \quad & (\textrm{Objective}) \\
    \textrm{s.t.} & \quad x_n \in \mathcal{X}_n,      \quad n \in \mathcal{N(\mathcal{G})}, \quad & (\textrm{Node Constraints})\\
    & \quad g_e(\{x_n\}_{n \in \mathcal{N}(e)}) = 0,  \quad e \in \mathcal{E(\mathcal{G})}. &(\textrm{Link Constraints})
\end{aligned}
```

An `OptiGraph` is composed of `OptiNodes` (which also extend the `JuMP.AbstractModel`) which represent modular optimization problems. `OptiNodes` are connected by `OptiEdges` which encapsulate `LinkConstraints` (i.e. linking
constraints that couple optinodes).

## Creating an OptiGraph
An `OptiGraph` does not require any arguments to construct:

```@meta
CurrentModule = Plasmo
DocTestSetup = quote
    using Plasmo
end
```

```jldoctest modeling
julia> graph1 = OptiGraph()
OptiGraph:
local nodes: 0, total nodes: 0
local link constraints: 0, total link constraints 0
local subgraphs: 0, total subgraphs 0
```

```@meta
DocTestSetup = nothing
```
An `OptiGraph` optimizer can be specified in the same way as in JuMP using [`JuMP.set_optimizer`](@ref).  An optimizer can be any
JuMP compatible solver or a custom developed Plasmo.jl solver interface (see the [Solvers](@ref) section).  
For example, we could construct an `OptiGraph` that uses the `Ipopt.Opimizer` from the Ipopt package as following:

```julia
julia> using Ipopt

set_optimizer(graph1,Ipopt.Optimizer)
```

## Adding OptiNodes
The most effective way to add optinodes to an optigraph is by using the [`@optinode`](@ref) macro.  The below piece of code adds the node `n1` to
the optigraph `graph1`.

```jldoctest modeling
julia> @optinode(graph1,n1)
OptiNode w/ 0 Variable(s)
```
It is also possible to create sets of optinodes with a single call to [`@optinode`](@ref) like shown in the below code snippet.
Here, we create two more optinodes which we refer to with the reference `nodes`. This input produces a `JuMP.DenseAxisArray` which
allows us to refer to each optinode using the produced index sets.  For example, `nodes[2]` and `nodes[3]` each return the corresponding
optinode.

```jldoctest modeling
julia> @optinode(graph1,nodes[2:3])
1-dimensional DenseAxisArray{OptiNode,1,...} with index sets:
    Dimension 1, 2:3
And data, a 2-element Array{OptiNode,1}:
 OptiNode w/ 0 Variable(s)
 OptiNode w/ 0 Variable(s)

julia> nodes[2]
OptiNode w/ 0 Variable(s)

julia> nodes[3]
OptiNode w/ 0 Variable(s)
```
Each optinode can have its underlying model constructed in a modular way.  Here we loop through each optinode in `graph1` using [getnodes](@ref)
and construct its underlying model by adding variables, a constraint, and objective function.
```jldoctest modeling
julia>  for node in getnodes(graph1)
            @variable(node,x >= 0)
            @variable(node, y >= 2)
            @constraint(node,x + y >= 3)
            @objective(node, Min, y)
        end
```

!! note

     The [`OptiNode`](@ref) extends `JuMP.AbstractModel` and supports most of the same JuMP macros. However, extending nonlinear functionality in JuMP is not yet supported, and so
     one must use [`@NLnodeconstraint`](@ref) as opposed `@NLconstraint` to create nonlinear constraints on an optinode.

Variables within an optinode can be accessed directly by indexing the associated symbol.  This enclosed variable space is useful for
referencing variables on different optinodes when creating linking constraints or optigraph objective functions.
```jldoctest modeling
julia> n1[:x]
x

julia> nodes[2][:y]
y
```

## Adding LinkConstraints (OptiEdges)

Linking constraints ([`LinkConstraint`](@ref)s are linear constraints that couple variables across different optinodes.  The simplest way to create a linking constraint
is to use the `@linkconstraint` macro.  This macro accepts the same input as the JuMP `@constraint` macro and creates linear constraints over multiple nodes within the same optigraph.

```jldoctest modeling
julia> @linkconstraint(graph1, n1[:x] + nodes[2][:x] + nodes[3][:x] == 3)
LinkConstraintRef(1, OptiEdge w/ 1 Constraint(s))
```

## Hierarchical Modeling

A fundamental feature of using optigraphs is that it is possible to create subgraphs (i.e. sub-optigraphs) within an optigraph.  This enables a hierarchical style of modeling that retains its modular aspects.
Subgraphs are defined using the [add_subgraph!](@ref) function which embeds an optigraph as a subgraph within a higher level optigraph. This is demonstrated in the below snippets.  

First, we create two new optigraphs in the same fashion we did above.

```jldoctest modeling
julia> graph2 = OptiGraph();

julia> @optinode(graph2,nodes2[1:3]);

julia>  for node in getnodes(graph2)
            @variable(node, x >= 0)
            @variable(node, y >= 2)
            @constraint(node,x + y >= 5)
            @objective(node, Min, y)
        end

julia> @linkconstraint(graph2, nodes2[1][:x] + nodes2[2][:x] + nodes2[3][:x] == 5);

julia> graph3 = OptiGraph();

julia> @optinode(graph3,nodes3[1:3]);

julia>  for node in getnodes(graph3)
            @variable(node, x >= 0)
            @variable(node, y >= 2)
            @constraint(node,x + y >= 5)
            @objective(node, Min, y)
        end

julia> @linkconstraint(graph3, nodes3[1][:x] + nodes3[2][:x] + nodes3[3][:x] == 7);
```

Now we have three optigraphs (`graph1`,`graph2`, and `graph3`), each with their own local optinodes and linking constraints (and optiedges).  
These optigraphs can be embedded into a higher level optigraph with the following snippet:

```jldoctest modeling
julia> graph0 = OptiGraph()
OptiGraph:
local nodes: 0, total nodes: 0
local link constraints: 0, total link constraints 0
local subgraphs: 0, total subgraphs 0

julia> add_subgraph!(graph0,graph1)
OptiGraph:
local nodes: 0, total nodes: 3
local link constraints: 0, total link constraints 1
local subgraphs: 1, total subgraphs 1

julia> add_subgraph!(graph0,graph2)
OptiGraph:
local nodes: 0, total nodes: 6
local link constraints: 0, total link constraints 2
local subgraphs: 2, total subgraphs 2

julia> add_subgraph!(graph0,graph3)
OptiGraph:
local nodes: 0, total nodes: 9
local link constraints: 0, total link constraints 3
local subgraphs: 3, total subgraphs 3
```
Here, we see the distinction between local and global (total) elements. For instance, after we add all three subgraphs
the higher level `graph0`, we see that `graph0` contains 0 local optinodes, but contains 9 total optinodes which are elements of its subgraphs. This hierarchical distinction is also
made for linking constraints (i.e. optiedges), as well as subgraphs.  With this hierarhical style of modeling, subgraphs can be nested recursively such that an optigraph might contain
local subgraphs, and the highest level optigraph contains all of the subgraphs.

A key benefit of this hierarchical approach is that linking constraints can be expressed both locally and globally.  For instance, we can now add a linking constraint to `graph0` that
connects optinodes in its subgraphs like following:
```jldoctest modeling
julia> @linkconstraint(graph0,nodes[3][:x] + nodes2[2][:x] + nodes3[1][:x] == 10)
LinkConstraintRef(1, OptiEdge w/ 1 Constraint(s))

julia> println(graph0)
OptiGraph:
local nodes: 0, total nodes: 9
local link constraints: 1, total link constraints 4
local subgraphs: 3, total subgraphs 3
```
We now observe that `graph0` contains 1 local linking constraint, and 4 total linking constraints (by including its subgraphs).
Put another way, the local linking constraint in `graph0` is a global constraint that connects each of its subgraphs. This hierarchical style of modeling
facilitates the construction of optimization problems that include diverse model components.  For instance, a power system could be modeled separately from a
natural gas system and they could be coupled in a higher level combined optigraph.  The hierarchical structure also enables the use of distributed optimization solvers which
we discuss more in the [Solvers](@ref) section.

## OptiGraph Attributes
There are a few primary function which can be used to query optigraph attributes. `getnodes` can be used to retrieve an array of
the local optinodes in an optigraph, whereas `all_nodes` will recursively retrieve all of the optinodes in an optigraph, including the nodes in its subgraphs.

```jldoctest modeling
julia> getnodes(graph1)
3-element Array{OptiNode,1}:
 OptiNode w/ 2 Variable(s)
 OptiNode w/ 2 Variable(s)
 OptiNode w/ 2 Variable(s)

julia> getnodes(graph0)
0-element Array{OptiNode,1}

julia> all_nodes(graph0)
9-element Array{OptiNode,1}:
 OptiNode w/ 2 Variable(s)
 OptiNode w/ 2 Variable(s)
 OptiNode w/ 2 Variable(s)
 OptiNode w/ 2 Variable(s)
 OptiNode w/ 2 Variable(s)
 OptiNode w/ 2 Variable(s)
 OptiNode w/ 2 Variable(s)
 OptiNode w/ 2 Variable(s)
 OptiNode w/ 2 Variable(s)

```

It is possible to query for optiedges, linking constraints, and subgraphs in the same way. We can query optiedges:
```jldoctest modeling
julia> getedges(graph1)
1-element Array{OptiEdge,1}:
 OptiEdge w/ 1 Constraint(s)

julia> getedges(graph0)
1-element Array{OptiEdge,1}:
 OptiEdge w/ 1 Constraint(s)

julia> all_edges(graph0)
4-element Array{OptiEdge,1}:
 OptiEdge w/ 1 Constraint(s)
 OptiEdge w/ 1 Constraint(s)
 OptiEdge w/ 1 Constraint(s)
 OptiEdge w/ 1 Constraint(s)
```
query linking constraints:
```jldoctest modeling
julia> getlinkconstraints(graph1)
1-element Array{LinkConstraint,1}:
 LinkConstraint{GenericAffExpr{Float64,VariableRef},MathOptInterface.EqualTo{Float64}}(x + x + x, MathOptInterface.EqualTo{Float64}(3.0))

julia> getlinkconstraints(graph0)
1-element Array{LinkConstraint,1}:
 LinkConstraint{GenericAffExpr{Float64,VariableRef},MathOptInterface.EqualTo{Float64}}(x + x + x, MathOptInterface.EqualTo{Float64}(10.0))

julia> all_linkconstraints(graph0)
4-element Array{LinkConstraint,1}:
 LinkConstraint{GenericAffExpr{Float64,VariableRef},MathOptInterface.EqualTo{Float64}}(x + x + x, MathOptInterface.EqualTo{Float64}(3.0))
 LinkConstraint{GenericAffExpr{Float64,VariableRef},MathOptInterface.EqualTo{Float64}}(x + x + x, MathOptInterface.EqualTo{Float64}(5.0))
 LinkConstraint{GenericAffExpr{Float64,VariableRef},MathOptInterface.EqualTo{Float64}}(x + x + x, MathOptInterface.EqualTo{Float64}(7.0))
 LinkConstraint{GenericAffExpr{Float64,VariableRef},MathOptInterface.EqualTo{Float64}}(x + x + x, MathOptInterface.EqualTo{Float64}(10.0))
```
and query subgraphs:
```jldoctest modeling
julia> getsubgraphs(graph0)
3-element Array{AbstractOptiGraph,1}:
 OptiGraph:
local nodes: 3, total nodes: 3
local link constraints: 1, total link constraints 1
local subgraphs: 0, total subgraphs 0

 OptiGraph:
local nodes: 3, total nodes: 3
local link constraints: 1, total link constraints 1
local subgraphs: 0, total subgraphs 0

 OptiGraph:
local nodes: 3, total nodes: 3
local link constraints: 1, total link constraints 1
local subgraphs: 0, total subgraphs 0
```

## Methods
Modeling with an `OptiGraph` encompasses various useful methods.  It is important to note that both the `OptiGraph` and the `OptiNode` are extensions of the `JuMP.AbstractModel` and can use many of the same methods.
We refer to the [JuMP Documentation](https://jump.dev/JuMP.jl/stable/) which describes most methods. Some select functions are also listed here.

### OptiGraph Methods
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
@NLnodeconstraint
@linkconstraint
getedge
getedges
all_edges
getlinkconstraints
all_linkconstraints
add_subgraph!
getsubgraphs
all_subgraphs
```

### Extended JuMP Methods
```@docs
JuMP.all_variables(::OptiNode)
JuMP.set_optimizer(::OptiGraph,::Any)
JuMP.objective_function(::OptiGraph)
JuMP.value(::OptiNode,::VariableRef)
JuMP.num_variables(::OptiGraph)
JuMP.num_constraints(::OptiGraph)
```

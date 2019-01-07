# Solvers

## JuMP Solvers
Any `MathProgBase` compliant JuMP solver can be used to solve a `ModelGraph` object.  In this case, the entire `ModelGraph` will be aggregated into a JuMP model and
will use the JuMP `solve` function.  The solution updates the `ModelGraph` nodes and `LinkConstraint`s with corresponding variable and dual values.

## Plasmo Solvers
Built-in Plasmo solvers include a `BendersSolver` and `LagrangeSolver`

### LagrangeSolver

The `LagrangeSolver` will perform a Lagrangean decomposition algorithm which will dualize all linking constraints for any arbitrary graph. It could be a tree, it could be a sequence of nodes connected (e.g. temporal decomposition), or it may even contain cycles.

#### Usage
`lagrangesolve(graph::ModelGraph;update_method,ϵ,timelimit,lagrangeheuristic,initialmultipliers,α,δ,maxnoimprove,cpbound)`, solves the graph using the lagrangean decomposition algorithm

A solver can also be created using `LagrangeSolver([options])`

#### Options

* `update_method` Multiplier update method
  * allowed values: `:subgradient, :probingsubgradient, :marchingstep, :intersectionstep, :cuttingplanes`
  * default: `:subgradient`
* `ϵ` Convergence tolerance
  - default: 0.001
* `timelimit` Algorithm time limit in seconds
  - default: 3600 (1 hour)
* `lagrangeheuristic` Function to solve the lagrangean heuristic. PlasmoAlgorithms provides 2 heuristic functions: `fixbinaries, fixintegers`
  - default: `fixbinaries`
* `initialmultipliers` initialization method for lagrangean multipliers. When `:relaxation` is selected the algorithm will use the multipliers from the LP relaxation
  - allowed values: `:zero,:relaxation`
  - default: `zero`
* `α` Initial value for the step parameter in subgradient methods
  - default: 2
* `δ` Shrinking factor for `α`
  - default: 0.5
* `maxnoimprove` Number of iterations without improvement before shrinking `α`
  - default: 3


#### Multiplier updated methods
It supports the following methods for updating the lagrangean multipliers:
* Subgradient
* Probing Subgradient
* Marching Step
* Intersection Step (experimental)
* Interactive
* Cutting Planes
* Cutting planes with trust region
* Levels

### BendersSolver

#### Usage

#### Options

## External Solvers

External parallel optimization solvers are available through [PlasmoSolverInterface.jl](https://github.com/jalving/PlasmoSolverInterface.jl.git).  This package can be added with:

```julia
using Pkg
Pkg.clone("https://github.com/jalving/PlasmoSolverInterface.jl")
```

### PipsSolver
The `PipsSolver` solves nonlinear optimization problems with [PIPS-NLP](https://github.com/Argonne-National-Laboratory/PIPS/tree/master/PIPS-NLP).

#### Usage

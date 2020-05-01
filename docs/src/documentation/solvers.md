# Solvers

## JuMP Solvers
Any `MathProgBase` compliant JuMP solver can be used to solve a `ModelGraph` object.  In this case, the entire `ModelGraph` will be aggregated into a JuMP model and
will use the JuMP `solve` function.  The solution updates the `ModelGraph` nodes and `LinkConstraint`s with corresponding variable and dual values.


## SchwarzSolver 

## PipsSolver
The `PipsSolver` solves nonlinear optimization problems with [PIPS-NLP](https://github.com/Argonne-National-Laboratory/PIPS/tree/master/PIPS-NLP).

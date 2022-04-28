# Solvers
Plasmo.jl is intended to support [MathOptInterface.jl](https://github.com/jump-dev/MathOptInterface.jl) solvers in the same way as JuMP, in addition to custom decomposition-based solvers that can use the graph structure.

## MathOptInterface/JuMP Solvers
Solvers with MathOptInterface.jl wrappers should be accessible to Plasmo.jl using standard JuMP commands (i.e. the `set_optimizer` and `optimize!` functions should work for an `OptiGraph`.) The list of available
JuMP solvers is extensive and can be found on the [JuMP documentation page](https://jump.dev/JuMP.jl/stable/installation/#Supported-solvers).

## Custom Plasmo.jl Solvers
The breadth of current custom Plasmo.jl solvers is still somewhat limited, but the solvers listed below provide a glimpse of future solver development. Please stay tuned for custom Plasmo.jl solver releases and updates.

### PipsNLP.jl
The [PipsNLP](https://github.com/zavalab/PipsNLP.jl) interface can be used to solve structured nonlinear optimization problems with [PIPS-NLP](https://github.com/Argonne-National-Laboratory/PIPS/tree/master/PIPS-NLP) using MPI.  The [examples folder](https://github.com/zavalab/PipsNLP.jl/tree/master/examples) in PipsNLP.jl shows how to use the Julia `MPIManager` as part of [MPIClusterManagers](https://github.com/JuliaParallel/MPIClusterManagers.jl) to model and optimize optigraphs in a distributed fashion. Note however, that it requires building an old commit specified on the PipsNLP.jl README.   

### SchwarzOpt.jl
The [SchwarzOpt](https://github.com/zavalab/SchwarzOpt.jl) optimizer is currently an experimental solver. It demonstrates how to use graph overlap to solve optigraphs with Schwarz decomposition.

### MadNLP
[MadNLP](https://github.com/MadNLP/MadNLP.jl) is an NLP solver that can solve `OptiGraphs` directly using parallel function evaluations and specialized decomposition schemes.

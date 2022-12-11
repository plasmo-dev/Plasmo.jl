# Solvers
Plasmo.jl is intended to support [MathOptInterface.jl](https://github.com/jump-dev/MathOptInterface.jl) solvers in the same way as JuMP.

## MathOptInterface.jl Solvers
Solvers with MathOptInterface.jl wrappers should be accessible to Plasmo.jl using standard JuMP functions (i.e. the [`set_optimizer`](@ref) and [`optimize!`](@ref) functions should work for an [`OptiGraph`](@ref) just like they do for a `JuMP.Model`) The list of available
JuMP solvers is extensive and can be found on the [JuMP documentation page](https://jump.dev/JuMP.jl/stable/installation/#Supported-solvers).

## Plasmo.jl Solvers
Specialized Plasmo.jl solvers are not yet supported, although this will change in the future as we define a standard solver interface. Please stay tuned for custom Plasmo.jl solver releases and updates.

<!-- ### MadNLP
[MadNLP](https://github.com/MadNLP/MadNLP.jl) is an NLP solver that can solve `OptiGraphs` directly using parallel function evaluations and specialized decomposition schemes.

### PipsNLP.jl
The [PipsNLP](https://github.com/plasmo-dev/PipsNLP.jl) interface can be used to solve structured nonlinear optimization problems with [PIPS-NLP](https://github.com/Argonne-National-Laboratory/PIPS/tree/master/PIPS-NLP) using MPI.  The [examples folder](https://github.com/zavalab/PipsNLP.jl/tree/master/examples) in PipsNLP.jl shows how to use the Julia `MPIManager` as part of [MPIClusterManagers](https://github.com/JuliaParallel/MPIClusterManagers.jl) to model and optimize optigraphs in a distributed fashion. Note however, that it requires building an old commit specified on the PipsNLP.jl README.   

### SchwarzOpt.jl
The [SchwarzOpt](https://github.com/plasmo-dev/SchwarzOpt.jl) optimizer is currently an experimental solver. It demonstrates how to use graph overlap to solve optigraphs with Schwarz decomposition. -->

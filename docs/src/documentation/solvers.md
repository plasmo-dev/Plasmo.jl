# Solvers
Plasmo.jl supports JuMP/MOI enabled solvers, as well as the [PIPS-NLP](https://github.com/Argonne-National-Laboratory/PIPS/tree/master/PIPS-NLP) parallel optimization solver.

## JuMP/MOI Solvers
Plasmo.jl can use JuMP/MOI solvers by means of its [`aggregate`](@ref) function.    
The example below solves an optigraph using `Ipopt`, where underneath, `optimize!` produces a single `OptiNode` (which encapsulates a `JuMP.Model`), solves the optinode, and populates the solution
of the optigraph with the result.

```julia
using Plasmo
using Ipopt

graph = OptiGraph()

@optinode(graph,n1)
@optinode(graph,n2)

@variable(n1,0 <= x <= 2)
@variable(n1,0 <= y <= 3)
@constraint(n1,x+y <= 4)
@objective(n1,Min,x)

@variable(n2,x)
@NLnodeconstraint(n2,exp(x) >= 2)

@linkconstraint(graph,n1[:x] == n2[:x])

ipopt = Ipopt.Optimizer
optimize!(graph,ipopt)
```

```@meta
CurrentModule = Plasmo
DocTestSetup = quote
    using Plasmo
    using Ipopt

    graph = OptiGraph()

    @optinode(graph,n1)
    @optinode(graph,n2)

    @variable(n1,0 <= x <= 2)
    @variable(n1,0 <= y <= 3)
    @constraint(n1,x+y <= 4)
    @objective(n1,Min,x)

    @variable(n2,x)
    @NLnodeconstraint(n2,exp(x) >= 2)

    @linkconstraint(graph,n1[:x] == n2[:x])

    ipopt = Ipopt.Optimizer
    optimize!(graph,ipopt)
end
```

A result specific to an optinode can be accessed using the `nodevalue` function.  Here we see that the value of `x` on  optinodes `n1` and `n2`
can be queried (and are consistent with the linking constraint).

```jldoctest solver_example
julia> println("n1[:x]= ",round(nodevalue(n1[:x]),digits = 5))
n1[:x]= 0.69315

julia> println("n2[:x]= ",round(nodevalue(n2[:x]),digits = 5))
n2[:x]= 0.69315
```

## PipsSolver
The [PipsSolver](https://github.com/zavalab/PipsSolver.jl) interface can be used to solve structured nonlinear optimization problems with [PIPS-NLP](https://github.com/Argonne-National-Laboratory/PIPS/tree/master/PIPS-NLP).
To do so, we use the [MPClusterManagers](https://github.com/JuliaParallel/MPIClusterManagers.jl) package and Julia's `Distributed` module to distribute an optigraph among worker CPUs.  We then execute PIPS-NLP using
MPI using `@mpi_do` (available from `MPIClusterManagers`) which runs MPI on each worker. The below example shows how this is done for a simple optigraph with two optinodes and two MPI ranks.

```julia
using MPIClusterManagers
using Distributed

# specify 2 MPI workers
manager=MPIManager(np=2)

# uses Distributed to add processors to a manager
addprocs(manager)

@everywhere using Plasmo
@everywhere using PipsSolver

julia_workers = collect(values(manager.mpi2j))

graph = OptiGraph()

@optinode(graph,n1)
@optinode(graph,n2)

@variable(n1,0 <= x <= 2)
@variable(n1,0 <= y <= 3)
@variable(n1, z >= 0)
@constraint(n1,x+y+z >= 4)
@objective(n1,Min,y)

@variable(n2,x)
@NLnodeconstraint(n2,ref,exp(x) >= 2)
@variable(n2,z >= 0)
@constraint(n2,z + x >= 4)
@objective(n2,Min,x)

@linkconstraint(graph,n1[:x] == n2[:x])

#Distribute the graph to workers.  #create the variable pipsgraph on each worker
remote_references = PipsSolver.distribute(graph,julia_workers,remote_name = :pipsgraph)

#Execute MPI
@mpi_do manager begin
    using MPI
    PipsSolver.pipsnlp_solve(pipsgraph)
end
```

## SchwarzSolver

Documentation Coming Soon

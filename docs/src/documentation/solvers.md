# Solvers
Plasmo.jl works with both JuMP/MOI enabled solvers.

## JuMP/MOI Solvers
Plasmo.jl can use JuMP/MOI solvers by means of model aggregation.  More specifically, all of the `OptiNodes` in an `OptiGraph` can be aggregated into a stand-alone JuMP model which can be used with
standard JuMP-enabled solvers.  The quickstart example (duplicated below) solves an `OptiGraph` using the Ipopt Julia interface for instance.  Underneath, this produces a JuMP model, solves it, and populates the
`OptiGraph` with the solution.

```julia
using Plasmo
using Ipopt

graph = OptiGraph()

#Add nodes to a ModelGraph
@optinode(graph,n1)
@optinode(graph,n2)

@variable(n1,0 <= x <= 2)
@variable(n1,0 <= y <= 3)
@constraint(n1,x+y <= 4)
@objective(n1,Min,x)

@variable(n2,x)
@NLnodeconstraint(n2,exp(x) >= 2)

#Add a linkconstraint
@linkconstraint(graph,n1[:x] == n2[:x])

ipopt = Ipopt.Optimizer
optimize!(graph,ipopt)

println("n1[:x]= ",value(n1,n1[:x]))
println("n2[:x]= ",value(n2,n2[:x]))
```

## PipsSolver
The `PipsSolver` package can be used to solve nonlinear optimization problems with [PIPS-NLP](https://github.com/Argonne-National-Laboratory/PIPS/tree/master/PIPS-NLP).
To do so, we use the `MPClusterManagers` package and Julia's `Distributed` package to distribute an `OptiGraph` among worker CPUs.  We then execute PIPS-NLP using
MPI using `@mpi_do` which runs MPI on each worker.

```julia
using MPIClusterManagers
using Distributed

# specify 2 MPI workers
manager=MPIManager(np=2)
addprocs(manager) #uses Distributed to add processors to manager

@everywhere using Plasmo
@everywhere using PipsSolver

julia_workers = collect(values(manager.mpi2j))

graph = OptiGraph()

#Add nodes to a GraphModel
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

#Link constraints take the same expressions as the JuMP @constraint macro
@linkconstraint(graph,n1[:x] == n2[:x])

#Distribute the graph to workers.  #create the variable pipsgraph on each worker
remote_references = PipsSolver.distribute(graph,julia_workers,remote_name = :pipsgraph)

#Execute MPI
@mpi_do manager begin
    using MPI
    PipsSolver.pipsnlp_solve(pipsgraph)
end
```

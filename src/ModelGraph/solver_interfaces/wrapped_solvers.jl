import MPI
using ParallelDataTransfer

#Benders Decomposition Solver
mutable struct PipsSolver <: AbstractPlasmoSolver
    options::Dict{Any,Any}
    status
end

function PipsSolver(;n_workers = 1,master = nothing, children = nothing)
    solver = PipsSolver(Dict(:n_workers => n_workers,:master => master,:children => children),nothing)
end

function solve(graph::ModelGraph,solver::PipsSolver)
    np = solver.options[:n_workers]
    manager = MPI.MPIManager(np = np)
    addprocs(manager)
    j_workers = collect(values(manager.mpi2j))
    master = solver.options[:master]
    children = solver.options[:children]
    if np > 0
        MPI.@mpi_do manager using Plasmo
        MPI.@mpi_do manager load_pips()
        @passobj 1 jworkers graph
        MPI.@mpi_do manager pipsnlp_solve(graph,master,children)
    end

    #pipsnlp_solve(graph,solver)
end

#load PIPS-NLP if the library can be found
function load_pips()
    if  !isempty(Libdl.find_library("libparpipsnlp"))
        #include("solver_interfaces/plasmoPipsNlpInterface3.jl")
        eval(quote using .PlasmoPipsNlpInterface3 end)
    else
        pipsnlp_solve(Any...) = throw(error("Could not find a PIPS-NLP installation"))
    end
end



#load DSP if the library can be found
# function load_dsp()
#     if !isempty(Libdl.find_library("libDsp"))
#         include("solver_interfaces/plasmoDspInterface.jl")
#         using .PlasmoDspInterface
#     else
#         dsp_solve(Any...) = throw(error("Could not find a DSP installation"))
#     end
# end

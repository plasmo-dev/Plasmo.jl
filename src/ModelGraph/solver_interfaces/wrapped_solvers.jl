import MPI


#Benders Decomposition Solver
mutable struct PipsSolver <: AbstractPlasmoSolver
    options::Dict{Any,Any}
    manager::MPI.MPIManager
    status
end

function PipsSolver(;n_workers = 1,master = nothing, children = nothing)
    solver = PipsSolver(Dict(:n_workers => n_workers,:master => master,:children => children),MPI.MPIManager(np = n_workers),nothing)
end

#TODO Better checking of PIPS library
function solve(graph::ModelGraph,solver::PipsSolver)
    !isempty(Libdl.find_library("libparpipsnlp")) || error("Could not find a PIPS-NLP installation")
    manager = solver.manager
    if length(manager.mpi2j) == 0
        addprocs(manager)
    end
    master = solver.options[:master]
    children = solver.options[:children]
    @assert length(children) + 1 == length(getnodes(graph))
    if manager.np > 0
        println("Preparing PIPS MPI environment")
        eval(quote @everywhere using Plasmo end)
        eval(quote @everywhere using Plasmo.PlasmoModelGraph.PlasmoPipsNlpInterface end)
        send_pips_data(manager,graph,master,children)
        println("Solving with PIPS-NLP")
        MPI.@mpi_do manager pipsnlp_solve(graph,master,children)
        #Get solution
        rank_zero = manager.mpi2j[0]
        sol = fetch(@spawnat(rank_zero, getfield(Main, :graph)))
        setsolution(sol,graph)
        return nothing
    end
end

function send_pips_data(manager::MPI.MPIManager,graph::ModelGraph,master::Int,children::Vector{Int})
    julia_workers = collect(values(manager.mpi2j))
    r = RemoteChannel(1)
    @spawnat(1, put!(r, [graph,master,children]))
    @sync for to in julia_workers
        @spawnat(to, Core.eval(Main, Expr(:(=), :graph, fetch(r)[1])))
        @spawnat(to, Core.eval(Main, Expr(:(=), :master, fetch(r)[2])))
        @spawnat(to, Core.eval(Main, Expr(:(=), :children, fetch(r)[3])))
    end
end

# #load PIPS-NLP if the library can be found
# function load_pips()
#     if  !isempty(Libdl.find_library("libparpipsnlp"))
#         #include("solver_interfaces/plasmoPipsNlpInterface3.jl")
#         #eval(quote using .PlasmoPipsNlpInterface3 end)
#         eval(macroexpand(quote @everywhere using .PlasmoPipsNlpInterface3 end))
#     else
#         pipsnlp_solve(Any...) = throw(error("Could not find a PIPS-NLP installation"))
#     end
# end

#load DSP if the library can be found
# function load_dsp()
#     if !isempty(Libdl.find_library("libDsp"))
#         include("solver_interfaces/plasmoDspInterface.jl")
#         using .PlasmoDspInterface
#     else
#         dsp_solve(Any...) = throw(error("Could not find a DSP installation"))
#     end
# end

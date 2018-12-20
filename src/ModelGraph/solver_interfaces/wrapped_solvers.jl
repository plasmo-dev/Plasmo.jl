import MPI
using Libdl

#Benders Decomposition Solver
mutable struct PipsSolver <: AbstractPlasmoSolver
    options::Dict{Symbol,Any}
    partition_options::Dict{Symbol,Any}
    manager::MPI.MPIManager
    status
end

function PipsSolver(;n_workers = 1,master = 0,children = nothing,partitions = Vector{Vector{Int64}}(),master_partition = Vector{Int64}())
    solver = PipsSolver(
    Dict(:n_workers => n_workers,:master => master,:children => children),
    Dict(:master_partition => master_partition,:sub_partitions => partitions),
    MPI.MPIManager(np = n_workers),
    nothing)
end

function solve(graph::ModelGraph,solver::PipsSolver)
    !isempty(Libdl.find_library("libparpipsnlp")) || error("Could not find a PIPS-NLP installation")

    #If we partition
    if !isempty(solver.partition_options[:sub_partitions])
        println("Using partitions for PIPS-NLP")
        pips_graph = create_pips_tree(graph,solver.partition_options[:sub_partitions];master_partition = solver.partition_options[:master_partition])
        master = pips_graph.master_node_index
        children = pips_graph.sub_node_indices
    else #just use master and child indices from original graph
        println("Using graph structure for PIPS-NLP")
        master = solver.options[:master]
        children = solver.options[:children]
        pips_graph = graph
    end

    manager = solver.manager
    if length(manager.mpi2j) == 0
        addprocs(manager)
    end

    #TODO better structure checks
    #@assert length(children) + 1 == length(getnodes(graph))

    println("Preparing PIPS MPI environment")
    eval(quote @everywhere using Plasmo end)
    eval(quote @everywhere using Plasmo.PlasmoModelGraph.PlasmoPipsNlpInterface end)

    send_pips_data(manager,pips_graph,master,children)

    println("Solving with PIPS-NLP")
    MPI.@mpi_do manager pipsnlp_solve(pips_graph,master,children)

    #Get solution
    rank_zero = manager.mpi2j[0]
    sol = fetch(@spawnat(rank_zero, getfield(Main, :pips_graph)))

    #Update the graph on the julia process if we used a PipsTree
    setsolution(sol,pips_graph)

    #Now move the pips_graph solution to the original model graph
    setsolution(pips_graph,graph)

    return nothing  #TODO retrieve solve status
end

function send_pips_data(manager::MPI.MPIManager,graph::AbstractModelGraph,master::Int,children::Vector{Int})
    julia_workers = collect(values(manager.mpi2j))
    r = RemoteChannel(1)
    @spawnat(1, put!(r, [graph,master,children]))
    @sync for to in julia_workers
        @spawnat(to, Core.eval(Main, Expr(:(=), :pips_graph, fetch(r)[1])))
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

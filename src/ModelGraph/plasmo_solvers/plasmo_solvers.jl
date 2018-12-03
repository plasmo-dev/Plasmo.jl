#Benders Decomposition Solver
mutable struct BendersSolver <: AbstractPlasmoSolver
    options::Dict{Any,Any}
    lp_solver::AbstractMathProgSolver
    node_solver::AbstractMathProgSolver
    structure           #structure has solver data
    solution
end

function BendersSolver(;max_iterations::Int64=10, cuts::Array{Symbol,1}=[:LP], ϵ=1e-5,UBupdatefrequency=1,timelimit=3600,verbose=false,lp_solver = JuMP.UnsetSolver(),node_solver = JuMP.UnsetSolver())
    solver = BendersSolver(Dict(:max_iterations => max_iterations,:cuts => cuts,:ϵ => ϵ, :UBupdatefrequency => UBupdatefrequency, :timelimit=>timelimit,:verbose => verbose),
    lp_solver,
    node_solver,
    nothing,
    nothing)
end

setlpsolver(bsolver::BendersSolver,lpsolver::AbstractMathProgSolver) = bsolver.lp_solver = lpsolver

#TODO: Create a duplicate model that includes the algorithm additions to the structure.  This would facilitate multiple solves of the same model.
function solve(tree::ModelTree,bsolver::BendersSolver)
    solution = bendersolve(tree;max_iterations = bsolver.options[:max_iterations], cuts = bsolver.options[:cuts],  ϵ = bsolver.options[:ϵ], UBupdatefrequency = bsolver.options[:UBupdatefrequency],
    timelimit = bsolver.options[:timelimit],verbose = bsolver.options[:verbose],lp_solver = bsolver.lp_solver,node_solver = bsolver.node_solver)
    bsolver.solution = solution
    return solution
end

#Lagrange decomposition solver
mutable struct LagrangeSolver <: AbstractPlasmoSolver
    options::Dict{Any,Any}
    cutting_plane_solver::AbstractMathProgSolver
    node_solver::AbstractMathProgSolver
    structure
    solution
end

function LagrangeSolver(;max_iterations=10,
    update_method=:subgradient,     #probingsubgradient
    ϵ=0.001,                        # ϵ-convergence tolerance
    timelimit=3600,
    α=2,                            # default subgradient step
    lagrangeheuristic=fixbinaries,  # function to calculate the upper bound
    initialmultipliers=:zero,       # :relaxation for LP relaxation
    δ = 0.5,                        # Factor to shrink step when subgradient stuck
    maxnoimprove = 3,
    cpbound=1e6,
    cutting_plane_solver = JuMP.UnsetSolver(),
    node_solver = JuMP.UnsetSolver())

    solver = LagrangeSolver(Dict(:max_iterations => max_iterations,:update_method => update_method,:ϵ => ϵ,:timelimit => timelimit,:α => α, :lagrangeheuristic => lagrangeheuristic,
            :initialmultipliers => initialmultipliers,:δ => δ, :maxnoimprove => maxnoimprove,:cpbound => cpbound),
            cutting_plane_solver,
            node_solver,
            nothing,
            nothing
    )

end

function solve(graph::ModelGraph,lagsolver::LagrangeSolver)
    solution = lagrangesolve(graph; cutting_plane_solver = lagsolver.cutting_plane_solver,node_solver = lagsolver.node_solver,lagsolver.options...)
    lagsolver.solution = solution
    return solution
end

include("utils.jl")

include("solution.jl")

include("benders.jl")

include("lagrange.jl")

# function benderssolve(tree::ModelTree,solver::BendersSolver)
#     #Braulio's benders code here
# end
#
# function benderssolve(graph::ModelGraph)
#     #Check model structure first
#     #Convert to ModelTree
# end

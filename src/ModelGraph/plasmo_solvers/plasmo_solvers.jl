#Benders Decomposition Solver
mutable struct BendersSolver <: AbstractPlasmoSolver
    options::Dict{Any,Any}
    lp_solver::AbstractMathProgSolver
    node_solver::AbstractMathProgSolver
    structure           #structure has solver data
    solution
end

function BendersSolver(;max_iterations::Int64=10, cuts::Array{Symbol,1}=[:LP], ϵ=1e-5,UBupdatefrequency=1,timelimit=3600,verbose=false,lp_solver = JuMP.UnsetSolver(),node_solver = JuMP.UnsetSolver())
    solver = BendersSolver(Dict(:max_iterations => max_iterations,:cuts => cuts,:ϵ => ϵ, :UBupdatefrequency => UBupdatefrequency, :timelimit=>timelimit,:verbose => verbose),lp_solver,node_solver,nothing,nothing)
end

setlpsolver(bsolver::BendersSolver,lpsolver::AbstractMathProgSolver) = bsolver.lp_solver = lpsolver

function solve(tree::ModelTree,bsolver::BendersSolver)
    status = bendersolve(tree;max_iterations = bsolver.options[:max_iterations], cuts = bsolver.options[:cuts],  ϵ = bsolver.options[:ϵ], UBupdatefrequency = bsolver.options[:UBupdatefrequency],
    timelimit = bsolver.options[:timelimit],verbose = bsolver.options[:verbose],lp_solver = bsolver.lp_solver,node_solver = bsolver.node_solver)
    return status
end



#Lagrange decomposition solver
mutable struct LagrangeSolver <: AbstractPlasmoSolver
    options::Dict{Any,Any}
    structure
    solution
end

function LagrangeSolver(tree::ModelTree,solver::LagrangeSolver)
    #Braulio's code here
end

include("utils.jl")

include("solution.jl")

include("benders.jl")

# function benderssolve(tree::ModelTree,solver::BendersSolver)
#     #Braulio's benders code here
# end
#
# function benderssolve(graph::ModelGraph)
#     #Check model structure first
#     #Convert to ModelTree
# end

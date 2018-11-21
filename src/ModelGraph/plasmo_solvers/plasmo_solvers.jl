#Interface for Braulio's PlasmoAlgorithms package
mutable struct BendersSolver <: AbstractPlasmoSolver
    options::Dict{Any,Any}
    structure  #structure has solver data
    solution
end

function BendersSolver(;max_iterations::Int64=10, cuts::Array{Symbol,1}=[:LP], ϵ=1e-5,UBupdatefrequency=1,timelimit=3600,verbose=false)
    solver = BendersSolver(Dict(:max_iterations => max_iterations,:cuts => cuts,:ϵ => ϵ, :UBupdatefrequency => UBupdatefrequency, :timelimit=>timelimit,:vecbose => verbose),nothing,nothing)
end

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

include("benders2.jl")

# function benderssolve(tree::ModelTree,solver::BendersSolver)
#     #Braulio's benders code here
# end
#
# function benderssolve(graph::ModelGraph)
#     #Check model structure first
#     #Convert to ModelTree
# end

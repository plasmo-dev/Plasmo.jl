#Interface for Braulio's PlasmoAlgorithms package
mutable struct BendersSolver <: AbstractPlasmoSolver
    options::Dict{Any,Any}
    structure  #structure has solver data
    solution
end

function benderssolve(tree::ModelTree,solver::BendersSolver)
    #Braulio's benders code here
end

function benderssolve(graph::ModelGraph)
    #Check model structure first
    #Convert to ModelTree
end

mutable struct LagrangeSolver <: AbstractPlasmoSolver
    options::Dict{Any,Any}
    structure
    solution
end

function lagrangesolve(tree::ModelTree,solver::LagrangeSolver)
    #Braulio's code here
end

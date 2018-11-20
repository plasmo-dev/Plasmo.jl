#Interface for Braulio's PlasmoAlgorithms package
abstract type AbstractPlasmoSolver end

mutable struct BendersSolver <: AbstractPlasmoSolver
    graph_structure::Union{Void,TwoStageTree}
end

function benders_solve(tree::ModelTree)
end

function benders_solve(graph::ModelGraph)
    #Check model structure first
    #Convert to ModelTree
end


mutable struct LagrangeSolver
    graph_structure
end

function lagrange_solve(graph::ModelGraph)
end

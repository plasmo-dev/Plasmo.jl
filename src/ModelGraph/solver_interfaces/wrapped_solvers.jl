#Benders Decomposition Solver
mutable struct PipsnlpSolver <: AbstractPlasmoSolver
    options::Dict{Any,Any}
    solution
end

function PipsnlpSolver()
end

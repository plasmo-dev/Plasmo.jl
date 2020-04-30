using Test

@testset "Testing core functions" begin
    include("modelgraph.jl")
    include("subgraphs.jl")
    include("partition.jl")
end

@testset "Testing nonlinear functions" begin
    include("add_NL_objectives.jl")
    include("nl_problem.jl")
end

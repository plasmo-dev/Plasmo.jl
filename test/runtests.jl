using Test

# @testset "$(file)" for file in filter(f -> endswith(f, ".jl"), readdir(@__DIR__))
#     if file == "runtests.jl"
#         continue
#     end
#     include(file)
# end

@testset "Core functions" begin
    include("modelgraph.jl")
    include("subgraphs.jl")
    include("partition.jl")
end

@testset "Nonlinear functions" begin
    include("add_NL_objectives.jl")
    include("nl_problem.jl")
end

@testset "Graph functions" begin
    include("hypergraph.jl")
end

using Test

@testset "$(file)" for file in filter(f -> endswith(f, ".jl"), readdir(@__DIR__))
    if file == "runtests.jl" || file == "solvers.jl"
        continue
    end
    include(file)
end

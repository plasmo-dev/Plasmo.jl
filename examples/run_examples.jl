using Test

const EXAMPLES = filter(ex -> endswith(ex, ".jl") && ex != "run_examples.jl",readdir(@__DIR__))

pushfirst!(LOAD_PATH,(@__DIR__)*"../")

@testset "run_examples.jl" begin
    @testset "$(example)" for example in EXAMPLES
        include(example)
    end
end

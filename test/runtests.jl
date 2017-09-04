using Plasmo
using Base.Test

#Test the graph functionality
@test include("graph_tests.jl")

#Test basic model functionality
@test include("model_tests.jl")

@test include("add_NL_objectives.jl")

#Special Test Problems
println("Running special test cases")
@test include("StochPIDTuning_Plasmo.jl")
@test include("test_problem_2.jl")

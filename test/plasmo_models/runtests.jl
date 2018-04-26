using Base.Test
#Test basic model functionality
println("Testing Basic Model Functions")
@test include("model_tests.jl")
@test include("test_modelgraph.jl")
@test include("test_jump_solve.jl")

println("Test adding nonlinear objectives")
@test include("add_NL_objectives.jl")

#Special Test Problems
println("Running special test cases")
@test include("test_stochastic_problem.jl")
@test include("test_stochastic_pid_problem.jl")

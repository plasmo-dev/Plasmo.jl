using Test
using Pkg
#Test basic model functionality
println("Testing Basic Model Functions")
@test include("link_constraint_1.jl")
@test include("link_constraint_2.jl")
@test include("solve_model_graph.jl")

println("Test adding nonlinear objectives")
@test include("add_NL_objectives.jl")

println("Test SolutionGraph")
@test include("solution_graph_1.jl")
@test include("solution_graph_2.jl")

#Plasmo Solvers
Pkg.add("GLPKMathProgInterface")
Pkg.clone("https://github.com/jalving/Metis.jl.git")

@test include("benders.jl")
@test include("lagrange.jl")

#Partition
@test include("partition.jl")

@test include("pips_aggregation.jl")

#Special Test Problems
println("Running special test cases")
@test include("test_problems/test_stochastic_problem.jl")
@test include("test_problems/test_stochastic_pid_problem.jl")

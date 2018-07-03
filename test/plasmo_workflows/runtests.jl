using Base.Test

#Test the graph functionality
println("Testing Workflow Functions")

println("Testing Simple Workflow")
@test include("test_simple_node.jl")

println("Testing Continuous Workflow")
@test include("test_continuous_node.jl")

using Test

println("Testing State Manager Functions")
@test include("test_state_manager.jl")

println("Testing Computing Graph Functions")

println("Testing Simple Computing Graph")
@test include("test_simple_node.jl")

println("Testing Continuous Node")
@test include("test_continuous_node.jl")

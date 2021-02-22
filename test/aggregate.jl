module TestAggregatation

using Plasmo
using Test

function test_affine_aggregate()
    graph = OptiGraph()

    n1 = @optinode(graph)
    n2 = @optinode(graph)

    @variable(n1,0 <= x <= 2)
    @variable(n1,0 <= y <= 3)
    @variable(n1, z >= 0)
    @constraint(n1,x+y+z >= 4)

    @variable(n2,x)
    @variable(n2,z >= 0)
    @constraint(n2,z + x >= 4)

    @linkconstraint(graph,n1[:x] == n2[:x])
    @linkconstraint(graph,n1[:z] == n2[:z])

    @objective(graph,Min,n1[:y] + n2[:x] + n1[:z])

    aggregate_node,reference_map = aggregate(graph)

    @test num_variables(graph) == 5
    @test num_variables(graph) == num_variables(aggregate_node)
end

function test_nonlinear_aggregate()
    graph = OptiGraph()
    @optinode(graph,n1)
    @variable(n1,x[1:2] <= 2)
    set_start_value(x[1],2)
    set_start_value(x[2],1)
    @NLobjective(n1,Max,x[1]^2 + x[2]^2)

    @optinode(graph,n2)
    @variable(n2,x[1:2] >= 0)
    set_start_value(x[1],2)
    set_start_value(x[2],2)
    @NLobjective(n2,Min,x[1]^3 + x[2]^2)

    new_node,ref = aggregate(graph)

    @test num_variables(graph) == 4
    @test num_variables(graph) == num_variables(new_node)

    #test start values
    all_vars = all_variables(new_node)
    @test all(start_value.(all_vars) .== [2,1,2,2])
end

function run_tests()
    for name in names(@__MODULE__; all = true)
        if !startswith("$(name)", "test_")
            continue
        end
        @testset "$(name)" begin
            getfield(@__MODULE__, name)()
        end
    end
end


end #module

TestAggregatation.run_tests()

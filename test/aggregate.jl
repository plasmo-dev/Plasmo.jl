module TestAggregatation

using Plasmo
using Test

function test_affine_aggregate()
end

function test_nonlinear_aggregate()
    graph = OptiGraph()
    @optinode(graph,n1)
    @variable(n1,x[1:2] <= 2)
    set_start_value(x[1],2)
    set_start_value(x[2],1)
    @NLobjective(n1,Max,x[1]^2 + x[2]^2)

    @optinode(graph,n2)
    @variable(n2,x[1:2] >= 0 )
    set_start_value(x[1],2)
    set_start_value(x[2],2)
    @NLobjective(n2,Min,x[1]^3 + x[2]^2)

    #TODO: fix nlp data with aggregation
    new_node,ref = aggregate(graph)

    @test num_variables(graph) == 4
    @test num_variables(graph) == num_variables(new_node)

    all_vars = all_variables(new_node)
    @test all(start_value.(all_vars) .== [2,1,2,2])

end

function runtests()
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

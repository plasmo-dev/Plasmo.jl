module TestMOIGraph

using Plasmo
using Ipopt
using Test

function test_graph_backend()
    graph = OptiGraph()
    gb = graph_backend(graph)

    
    # @test MOIU.state(gb) == MOIU.NO_OPTIMIZER

    # MOI.set(gb, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    # @test MOI.get(gb, MOI.ObjectiveSense()) == MOI.MIN_SENSE

    # set_optimizer(graph, Ipopt.Optimizer)
    # MOIU.attach_optimizer(graph)
    # @test typeof(backend(graph).optimizer.model) == Ipopt.Optimizer
end

function run_tests()
    for name in names(@__MODULE__; all=true)
        if !startswith("$(name)", "test_")
            continue
        end
        @testset "$(name)" begin
            getfield(@__MODULE__, name)()
        end
    end
end

end

TestMOIGraph.run_tests()

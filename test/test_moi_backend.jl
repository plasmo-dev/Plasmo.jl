# TODO: specific tests for MOI backend. 

module TestMOIGraph

using Plasmo
using Ipopt
using Test

function test_graph_backend()
    graph = OptiGraph()
    gb = graph_backend(graph)
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

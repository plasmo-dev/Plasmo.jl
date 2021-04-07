module TestHyperGraph

using Plasmo
using LightGraphs
using Test

function test_hypergraph()
    hyper = HyperGraph()
    add_node!(hyper)
    add_node!(hyper)
    add_node!(hyper)
    add_node!(hyper)
    add_node!(hyper)
    add_node!(hyper)

    Plasmo.add_hyperedge!(hyper,1,2,3)
    Plasmo.add_hyperedge!(hyper,1,2)
    Plasmo.add_hyperedge!(hyper,4,1,3)

    @test hyper.hyperedge_map[1] == HyperEdge(1,2,3)
    @test hyper.hyperedge_map[2] == HyperEdge(1,2)
    @test hyper.hyperedge_map[3] == HyperEdge(1,3,4)

    @test Set([1,2,3]) == hyper.hyperedge_map[1].vertices
    @test Set([1,2]) == hyper.hyperedge_map[2].vertices
    @test Set([1,3,4]) == hyper.hyperedge_map[3].vertices

    @test length(hyper.vertices) == 6
    @test length(hyper.hyperedge_map) == 3

    #4 vertices are connected by 3 hyperedges
    A = incidence_matrix(hyper)
    @test size(A) == (4,3)

    #Project to standard graph
    # clique_graph,graph_map= clique_graph)
    # @test nv(clique_graph) == 6
    # @test ne(clique_graph) == 5

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

end

TestHyperGraph.run_tests()

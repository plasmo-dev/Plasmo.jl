module TestGraphRepresentations

using Plasmo
using LightGraphs
using Test

function test_hypergraph()
    hyper = Plasmo.HyperGraph()
    add_node!(hyper)
    add_node!(hyper)
    add_node!(hyper)
    add_node!(hyper)
    add_node!(hyper)
    add_node!(hyper)

    Plasmo.add_hyperedge!(hyper,1,2,3)
    Plasmo.add_hyperedge!(hyper,1,2)
    Plasmo.add_hyperedge!(hyper,4,1,3)

    @test hyper.hyperedge_map[1] == Plasmo.HyperEdge(1,2,3)
    @test hyper.hyperedge_map[2] == Plasmo.HyperEdge(1,2)
    @test hyper.hyperedge_map[3] == Plasmo.HyperEdge(1,3,4)

    @test Set([1,2,3]) == hyper.hyperedge_map[1].vertices
    @test Set([1,2]) == hyper.hyperedge_map[2].vertices
    @test Set([1,3,4]) == hyper.hyperedge_map[3].vertices

    @test length(hyper.vertices) == 6
    @test length(hyper.hyperedge_map) == 3

    #4 vertices are connected by 3 hyperedges
    A = incidence_matrix(hyper)
    @test size(A) == (4,3)
end

function test_clique_graph()
    graph = Plasmo.CliqueGraph()
    add_vertex!(graph)
    add_vertex!(graph)
    add_vertex!(graph)
    @test nv(graph) == 3
    add_edge!(graph,1,2)
    add_edge!(graph,2,3)
    add_edge!(graph,1,3)
    @test ne(graph) == 3
end

function test_bipartite_graph()
    graph = Plasmo.BipartiteGraph()

    #optinodes => vertices
    add_vertex!(graph,bipartite = 1)
    add_vertex!(graph,bipartite = 1)
    add_vertex!(graph,bipartite = 1)
    @test nv(graph) == 3

    add_vertex!(graph,bipartite = 2)
    add_vertex!(graph,bipartite = 2)
    add_vertex!(graph,bipartite = 2)
    @test nv(graph) == 6

    add_edge!(graph,1,4)
    add_edge!(graph,2,5)
    add_edge!(graph,3,6)
    @test ne(graph) == 3
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

TestGraphRepresentations.run_tests()

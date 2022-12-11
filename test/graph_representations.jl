module TestGraphRepresentations

using Plasmo
using LightGraphs
using SparseArrays
using Test

function test_hypergraph()
    hyper = Plasmo.HyperGraph()
    add_node!(hyper)
    add_node!(hyper)
    add_node!(hyper)
    add_node!(hyper)
    add_node!(hyper)
    add_node!(hyper)

    @test getnode(hyper, 1) == hyper.vertices[1]
    @test Base.getindex(hyper, 1) == 1
    @test getnodes(hyper) == [1, 2, 3, 4, 5, 6]
    @test length(hyper.vertices) == 6
    @test LightGraphs.vertices(hyper) == [1, 2, 3, 4, 5, 6]

    Plasmo.add_hyperedge!(hyper, 1, 2, 3)
    Plasmo.add_hyperedge!(hyper, 1, 2)
    LightGraphs.add_edge!(hyper, 4, 1, 3)
    LightGraphs.add_edge!(hyper, 4, 5, 6)
    @test length(hyper.hyperedge_map) == 4
    @test hyper.hyperedge_map[1] == Plasmo.HyperEdge(1, 2, 3)
    @test hyper.hyperedge_map[2] == Plasmo.HyperEdge(1, 2)
    @test hyper.hyperedge_map[3] == Plasmo.HyperEdge(1, 3, 4)
    @test collect(Plasmo.gethyperedges(hyper)) == [1, 2, 3, 4]
    @test collect(Plasmo.getedges(hyper)) == [1, 2, 3, 4]

    e1 = Plasmo.gethyperedge(hyper, 1)
    @test_throws Exception Base.reverse(e1)
    @test sort(Plasmo.gethypernodes(e1)) == [1, 2, 3]
    @test sort(LightGraphs.vertices(e1)) == [1, 2, 3]
    @test Set([1, 2, 3]) == hyper.hyperedge_map[1].vertices
    @test Set([1, 2]) == hyper.hyperedge_map[2].vertices
    @test Set([1, 3, 4]) == hyper.hyperedge_map[3].vertices
    @test Base.getindex(hyper, e1) == 1

    @test LightGraphs.edgetype(hyper) == Plasmo.HyperEdge
    @test LightGraphs.has_edge(hyper, e1) == true
    @test LightGraphs.has_edge(hyper, Set([1, 2, 3])) == true
    @test LightGraphs.has_vertex(hyper, 1) == true
    @test LightGraphs.has_vertex(hyper, 10) == false
    @test LightGraphs.is_directed(hyper) == false
    @test LightGraphs.ne(hyper) == 4
    @test LightGraphs.nv(hyper) == 6
    @test LightGraphs.degree(hyper, 1) == 3
    @test LightGraphs.all_neighbors(hyper, 1) == [2, 3, 4]

    #4 vertices are connected by 3 hyperedges
    A = LightGraphs.incidence_matrix(hyper)
    @test size(A) == (6, 4)
    @test SparseArrays.nnz(A) == 11

    B = LightGraphs.adjacency_matrix(hyper)
    @test SparseArrays.nnz(B) == 16

    @test SparseArrays.sparse(hyper) == A

    @test Plasmo.incident_edges(hyper, 1) ==
        [Plasmo.HyperEdge(1, 2, 3), Plasmo.HyperEdge(1, 2), Plasmo.HyperEdge(1, 3, 4)]

    @test Plasmo.induced_edges(hyper, [1, 2, 3]) ==
        [Plasmo.HyperEdge(1, 2, 3), Plasmo.HyperEdge(1, 2)]

    @test Plasmo.incident_edges(hyper, [1, 2]) ==
        [Plasmo.HyperEdge(1, 2, 3), Plasmo.HyperEdge(1, 3, 4)]

    partition_vector = [[1, 2, 3], [4, 5, 6]]
    p, cross = Plasmo.identify_edges(hyper, partition_vector)
    @test p ==
        [[Plasmo.HyperEdge(1, 2, 3), Plasmo.HyperEdge(1, 2)], [Plasmo.HyperEdge(4, 5, 6)]]
    @test cross == Plasmo.HyperEdge[Plasmo.HyperEdge(1, 3, 4)]
    @test Plasmo.induced_elements(hyper, partition_vector) == partition_vector

    hedges = collect(values(hyper.hyperedge_map))
    partition_vector = [hedges[1:2], hedges[3:4]]
    p, cross = Plasmo.identify_nodes(hyper, partition_vector)
    @test p == [[2], [4, 5, 6]]
    @test cross == [1, 3]

    @test Plasmo.neighborhood(hyper, [1, 2], 1) == [1, 2, 3, 4]
    @test Plasmo.neighborhood(hyper, [1, 2], 2) == [1, 2, 3, 4, 5, 6]

    new_nodes, new_edges = Plasmo.expand(hyper, [1, 2], 1)
    @test new_nodes == [1, 2, 3, 4]
    @test new_edges == hedges[1:3]

    @test_throws Exception LightGraphs.rem_edge!(hyper, e1)
    @test_throws Exception LightGraphs.rem_vertex!(hyper, 1)
end

function test_clique_graph()
    graph = Plasmo.CliqueGraph()

    add_vertex!(graph)
    add_vertex!(graph)
    add_vertex!(graph)
    @test nv(graph) == 3

    add_edge!(graph, 1, 2)
    add_edge!(graph, 2, 3)
    add_edge!(graph, 1, 3)
    @test ne(graph) == 3

    @test collect(LightGraphs.edges(graph)) == [Edge(1, 2), Edge(1, 3), Edge(2, 3)]
    @test LightGraphs.edgetype(graph) == LightGraphs.SimpleGraphs.SimpleEdge{Int64}
    @test LightGraphs.has_edge(graph, 1, 2) == true
    @test LightGraphs.has_edge(graph, 1, 5) == false
    @test LightGraphs.has_vertex(graph, 1) == true
    @test LightGraphs.has_vertex(graph, 5) == false
    @test LightGraphs.is_directed(graph) == false
    @test LightGraphs.ne(graph) == 3
    @test LightGraphs.nv(graph) == 3
    @test LightGraphs.vertices(graph) == [1, 2, 3]

    @test LightGraphs.all_neighbors(graph, 1) == [2, 3]

    A = LightGraphs.incidence_matrix(graph)
    @test length(A) == 9
    @test SparseArrays.nnz(A) == 6
end

function test_bipartite_graph()
    graph = Plasmo.BipartiteGraph()

    #optinodes => vertices
    add_vertex!(graph; bipartite=1)
    add_vertex!(graph; bipartite=1)
    add_vertex!(graph; bipartite=1)
    @test nv(graph) == 3

    add_vertex!(graph; bipartite=2)
    add_vertex!(graph; bipartite=2)
    @test nv(graph) == 5
    @test LightGraphs.vertices(graph) == Base.OneTo(5)

    @test_throws Exception add_edge!(graph, 1, 2)
    add_edge!(graph, 1, 4)
    add_edge!(graph, 2, 4)
    add_edge!(graph, 2, 5)
    add_edge!(graph, 3, 5)
    @test ne(graph) == 4

    @test length(LightGraphs.edges(graph)) == 4
    @test LightGraphs.edgetype(graph) == LightGraphs.SimpleGraphs.SimpleEdge{Int64}
    @test LightGraphs.has_edge(graph, 1, 4) == true
    @test LightGraphs.has_edge(graph, 1, 2) == false
    @test LightGraphs.is_directed(graph) == false

    A = LightGraphs.adjacency_matrix(graph)
    @test length(A) == 6
    @test SparseArrays.nnz(A) == 4

    #nodes [1 and 2 and edge 4], [node 3 and edge 5]
    part_vector = [[1, 2, 4], [3, 5]]
    p, cross = Plasmo._identify_separators(
        graph, part_vector; cut_selector=LightGraphs.degree
    )
    @test p == [[1, 4], [3, 5]]
    @test cross == [2]

    part = Plasmo.induced_elements(graph, part_vector; cut_selector=LightGraphs.degree)
    @test part == p

    p, cross = Plasmo._identify_separators(graph, part_vector; cut_selector=:vertex)
    @test p == [[1, 4], [3, 5]]
    @test cross == [2]

    p, cross = Plasmo._identify_separators(graph, part_vector; cut_selector=:edge)
    @test p == [[1, 2, 4], [3]]
    @test cross == [5]
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

TestGraphRepresentations.run_tests()

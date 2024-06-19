module TestGraphRepresentations

using Plasmo
using SparseArrays
using Test

function _create_simple_optigraph()
    graph = OptiGraph()
    @optinode(graph, nodes[1:4])

    #node 1
    @variable(nodes[1], 0 <= x <= 2)
    @variable(nodes[1], 0 <= y <= 3)
    @constraint(nodes[1], 0 <= x + y <= 4)
    @objective(nodes[1], Min, x)

    #node 2
    @variable(nodes[2], x >= 1)
    @variable(nodes[2], 0 <= y <= 5)
    @constraint(nodes[2], exp(x) + y <= 7)
    @objective(nodes[2], Min, x)

    #node 3
    @variable(nodes[3], x >= 0)
    @variable(nodes[3], y >= 0)
    @constraint(nodes[3], x + y == 2)
    @objective(nodes[3], Max, x)

    #node 4
    @variable(nodes[4], 0 <= x <= 1)
    @variable(nodes[4], y >= 0)
    @constraint(nodes[4], x + y <= 3)
    @objective(nodes[4], Max, y)

    @linkconstraint(graph, nodes[1][:x] == nodes[2][:x])
    @linkconstraint(graph, nodes[2][:y] == nodes[3][:x])
    @linkconstraint(graph, nodes[3][:x] == nodes[4][:x])
    set_to_node_objectives(graph)
    return graph
end

function test_projection_hypergraph()
    graph = _create_simple_optigraph()
    projection = hyper_projection(graph)

    # TODO: get mapped elements
end

function test_projection_clique()
    graph = _create_simple_optigraph()
    projection = clique_projection(graph)
end

function test_projection_bipartite()
    graph = _create_simple_optigraph()
    projection = bipartite_projection(graph)
end

# function test_bipartite_graph()
#     graph = Plasmo.BipartiteGraph()

#     #optinodes => vertices
#     add_vertex!(graph; bipartite=1)
#     add_vertex!(graph; bipartite=1)
#     add_vertex!(graph; bipartite=1)
#     @test nv(graph) == 3

#     add_vertex!(graph; bipartite=2)
#     add_vertex!(graph; bipartite=2)
#     @test nv(graph) == 5
#     @test LightGraphs.vertices(graph) == Base.OneTo(5)

#     @test_throws Exception add_edge!(graph, 1, 2)
#     add_edge!(graph, 1, 4)
#     add_edge!(graph, 2, 4)
#     add_edge!(graph, 2, 5)
#     add_edge!(graph, 3, 5)
#     @test ne(graph) == 4

#     @test length(LightGraphs.edges(graph)) == 4
#     @test LightGraphs.edgetype(graph) == LightGraphs.SimpleGraphs.SimpleEdge{Int64}
#     @test LightGraphs.has_edge(graph, 1, 4) == true
#     @test LightGraphs.has_edge(graph, 1, 2) == false
#     @test LightGraphs.is_directed(graph) == false

#     A = LightGraphs.adjacency_matrix(graph)
#     @test length(A) == 6
#     @test SparseArrays.nnz(A) == 4

#     #nodes [1 and 2 and edge 4], [node 3 and edge 5]
#     part_vector = [[1, 2, 4], [3, 5]]
#     p, cross = Plasmo._identify_separators(
#         graph, part_vector; cut_selector=LightGraphs.degree
#     )
#     @test p == [[1, 4], [3, 5]]
#     @test cross == [2]

#     part = Plasmo.induced_elements(graph, part_vector; cut_selector=LightGraphs.degree)
#     @test part == p

#     p, cross = Plasmo._identify_separators(graph, part_vector; cut_selector=:vertex)
#     @test p == [[1, 4], [3, 5]]
#     @test cross == [2]

#     p, cross = Plasmo._identify_separators(graph, part_vector; cut_selector=:edge)
#     @test p == [[1, 2, 4], [3]]
#     @test cross == [5]
# end

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

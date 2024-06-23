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
    @test true
    # TODO: test get_mapped_elements
end

function test_projection_clique()
    graph = _create_simple_optigraph()
    projection = clique_projection(graph)
    @test true
end

function test_projection_edge_clique()
    graph = _create_simple_optigraph()
    projection = edge_clique_projection(graph)
    @test true
end

function test_projection_edge_hypergraph()
    graph = _create_simple_optigraph()
    projection = edge_hyper_projection(graph)
    @test true
end

function test_projection_bipartite()
    graph = _create_simple_optigraph()
    projection = bipartite_projection(graph)
    @test true
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

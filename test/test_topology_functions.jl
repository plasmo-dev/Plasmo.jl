module TestGraphFunctions

using Plasmo
using Graphs
using Test

function _create_test_optigraph()
    graph = OptiGraph()
    @optinode(graph, nodes[1:4])

    #node 1
    @variable(nodes[1], 0 <= x <= 2)
    @variable(nodes[1], 0 <= y <= 3)
    @constraint(nodes[1], 0 <= x + y <= 4)

    #node 2
    @variable(nodes[2], x >= 1)
    @variable(nodes[2], 0 <= y <= 5)
    @constraint(nodes[2], exp(x) + y <= 7)

    #node 3
    @variable(nodes[3], x >= 0)
    @variable(nodes[3], y >= 0)
    @constraint(nodes[3], x + y == 2)

    #node 4
    @variable(nodes[4], 0 <= x <= 1)
    @variable(nodes[4], y >= 0)
    @constraint(nodes[4], x + y <= 3)

    @linkconstraint(graph, nodes[1][:x] == nodes[2][:x])
    @linkconstraint(graph, nodes[2][:y] == nodes[3][:x])
    @linkconstraint(graph, nodes[3][:x] == nodes[4][:x])
    return graph
end

function _create_chain_optigraph()
    graph = OptiGraph()
    @optinode(graph, nodes[1:100])
    for node in nodes
        @variable(node, x >= 0)
    end
    for j in 1:99
        @linkconstraint(graph, nodes[j][:x] == nodes[j + 1][:x])
    end
    return graph
end

function test_hypergraph_functions()
    graph = _create_test_optigraph()

    n1 = get_node(graph, 1)
    n2 = get_node(graph, 2)
    n3 = get_node(graph, 3)

    projection = hyper_projection(graph)

    @test Graphs.all_neighbors(projection, n1) == [n2]
    @test Graphs.all_neighbors(projection, n2) == [n1, n3]

    # 3 nodes and 2 edges
    induced_graph_1 = Graphs.induced_subgraph(projection, [n1, n2, n3])
    @test num_nodes(induced_graph_1) == 3
    @test num_edges(induced_graph_1) == 2

    #2 nodes and no edges
    induced_graph_2 = Graphs.induced_subgraph(projection, [n1, n3])
    @test num_nodes(induced_graph_2) == 2
    @test num_edges(induced_graph_2) == 0

    e1 = get_edge_by_index(graph, 1)
    e2 = get_edge_by_index(graph, 2)
    incident_edges_1 = incident_edges(projection, n2)
    @test incident_edges_1 == [e1, e2]

    incident_edges_2 = incident_edges(projection, [n1, n2, n3])
    n4 = get_node(graph, 4)
    e3 = get_edge(graph, n3, n4)
    @test length(incident_edges_2) == 1
    @test incident_edges_2[1] == e3

    induced_edges_1 = induced_edges(projection, [n1, n2, n3])
    @test induced_edges_1 == [e1, e2]

    neigh = Graphs.neighborhood(projection, [n2, n3], 1)
    @test Set(neigh) == Set([n1, n2, n3, n4])

    expanded_graph_1 = expand(projection, [n1, n2], 1)
    @test all_nodes(expanded_graph_1) == [n1, n2, n3]

    expanded_graph_2 = expand(projection, [n1, n2], 2)
    @test all_nodes(expanded_graph_2) == [n1, n2, n3, n4]
end

function test_identify_functions()
    graph = _create_chain_optigraph()

    graph_nodes = all_nodes(graph)

    node_vectors = [
        graph_nodes[1:20],
        graph_nodes[21:40],
        graph_nodes[41:60],
        graph_nodes[61:80],
        graph_nodes[81:100],
    ]
    projection = hyper_projection(graph)

    identified_edges = identify_edges(projection, node_vectors)
    @test length(identified_edges[1]) == 5 #5 partitions
    @test length(identified_edges[2]) == 4 #4 linking edges

    graph_edges = all_edges(graph)
    edge_vectors = [
        graph_edges[1:20],
        graph_edges[21:40],
        graph_edges[41:60],
        graph_edges[61:80],
        graph_edges[81:99],
    ]
    identified_nodes = identify_nodes(projection, edge_vectors)
    @test length(identified_nodes[1]) == 5
    @test length(identified_nodes[2]) == 4
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

TestGraphFunctions.run_tests()

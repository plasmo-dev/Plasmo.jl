#  Copyright 2021, Jordan Jalving, Yankai Cao, Victor Zavala, and contributors
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at https://mozilla.org/MPL/2.0/.

module TestPartition

using Plasmo
using KaHyPar
using Ipopt
using Suppressor
using Test

kahypar_config = (@__DIR__) * "/cut_kKaHyPar_sea20.ini"

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

function test_partition_manual()
    graph = _create_chain_optigraph()
    nodes = all_nodes(graph)

    @objective(graph, Min, sum(all_variables(graph)))
    set_optimizer(graph, optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0))
    optimize!(graph)
    obj_val = objective_value(graph)

    A = reshape(nodes, 20, 5)
    node_vectors = [A[c, :] for c in 1:size(A, 1)]
    partition = Partition(graph, node_vectors)
    @test n_subpartitions(partition) == 20
    @test length(all_subpartitions(partition)) == 20
    @test length(all_nodes(partition)) == 100

    # test `assemble_optigraph` from partition
    new_graph = assemble_optigraph(partition)
    @test num_nodes(new_graph) == 100
    @test num_local_nodes(new_graph) == 0
    # check that objective values are the same
    @objective(new_graph, Min, sum(all_variables(new_graph)))
    set_optimizer(new_graph, optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0))
    optimize!(new_graph)

    # test `apply_partition!` and modify original graph
    apply_partition!(graph, partition)
    @test num_local_nodes(graph) == 0
    @test num_nodes(graph) == 100

    # check that objective values are the same
    @objective(graph, Min, sum(all_variables(graph)))
    set_optimizer(graph, optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0))
    optimize!(graph)

    @test objective_value(graph) == obj_val
end

function test_partition_node_membership_vector()
    graph = _create_simple_optigraph()
    n1, n2, n3, n4 = all_nodes(graph)
    node_membership_vector = [0, 0, 1, 1]
    partition = Partition(graph, node_membership_vector)
    @test n_subpartitions(partition) == 2
    @test partition.subpartitions[1].optinodes == [n1, n2]
    @test partition.subpartitions[2].optinodes == [n3, n4]
    new_graph = assemble_optigraph(partition)
    @test num_nodes(new_graph) == 4
    @test num_edges(new_graph) == 3
    @test num_subgraphs(new_graph) == 2
    @test num_local_nodes(new_graph) == 0
    @test num_local_edges(new_graph) == 1
end

function test_partition_node_vectors()
    graph = _create_simple_optigraph()
    n1, n2, n3, n4 = all_nodes(graph)
    node_vectors = [[n1, n2], [n3, n4]]
    partition = Partition(graph, node_vectors)
    @test n_subpartitions(partition) == 2
    @test partition.subpartitions[1].optinodes == [n1, n2]
    @test partition.subpartitions[2].optinodes == [n3, n4]
    new_graph = assemble_optigraph(partition)
    @test num_nodes(new_graph) == 4
    @test num_edges(new_graph) == 3
    @test num_subgraphs(new_graph) == 2
    @test num_local_nodes(new_graph) == 0
    @test num_local_edges(new_graph) == 1
end

function test_partition_hypergraph()
    graph = _create_simple_optigraph()
    projection = hyper_projection(graph)
    partition_vector = @suppress KaHyPar.partition(
        projection, 2; configuration=kahypar_config
    )
    partition = Partition(projection, partition_vector)
    new_graph = assemble_optigraph(partition)
    @test num_nodes(new_graph) == 4
    @test num_edges(new_graph) == 3
    @test num_subgraphs(new_graph) == 2
    @test num_local_nodes(new_graph) == 0
    @test num_local_edges(new_graph) == 1
end

function test_partition_clique()
    graph = _create_simple_optigraph()
    projection = clique_projection(graph)
    partition_vector = @suppress KaHyPar.partition(
        projection, 2; configuration=kahypar_config
    )
    partition = Partition(projection, partition_vector)
    new_graph = assemble_optigraph(partition)
    @test num_nodes(new_graph) == 4
    @test num_edges(new_graph) == 3
    @test num_subgraphs(new_graph) == 2
    @test num_local_nodes(new_graph) == 0
    @test num_local_edges(new_graph) == 1
end

function test_partition_edge_clique()
    graph = _create_simple_optigraph()
    projection = edge_clique_projection(graph)
    partition_vector = @suppress KaHyPar.partition(
        projection, 2; configuration=kahypar_config
    )
    partition = Partition(projection, partition_vector)
    @test n_subpartitions(partition) == 2
    new_graph = assemble_optigraph(partition)
    @test num_nodes(new_graph) == 4
    @test num_edges(new_graph) == 3
    @test num_subgraphs(new_graph) == 2
    @test num_local_nodes(new_graph) == 1
    @test num_local_edges(new_graph) == 2
end

function test_partition_edge_hypergraph()
    graph = _create_simple_optigraph()
    projection = edge_hyper_projection(graph)
    partition_vector = @suppress KaHyPar.partition(
        projection, 2; configuration=kahypar_config
    )
    partition = Partition(projection, partition_vector)
    @test n_subpartitions(partition) == 2
    new_graph = assemble_optigraph(partition)
    @test num_nodes(new_graph) == 4
    @test num_edges(new_graph) == 3
    @test num_subgraphs(new_graph) == 2
    @test num_local_nodes(new_graph) == 1
    @test num_local_edges(new_graph) == 2
end

function test_bipartite_1()
    graph = _create_simple_optigraph()
    projection = bipartite_projection(graph)
    partition_vector = @suppress KaHyPar.partition(
        projection, 2; configuration=kahypar_config
    )
    @test length(partition_vector) == 7
    partition = Partition(projection, partition_vector; cut_selector=:vertex)
    new_graph = assemble_optigraph(partition)
    @test num_nodes(new_graph) == 4
    @test num_edges(new_graph) == 3
    @test num_subgraphs(new_graph) == 2
    @test num_local_nodes(new_graph) == 1
    @test num_local_edges(new_graph) == 2

    #TODO
    #partition = Partition(bg,partition_vector,b_map; cut_selector = :edge)
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

TestPartition.run_tests()

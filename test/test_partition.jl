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

    # test `assemble_optigraph`
    new_graph = assemble_optigraph(partition)
    @test num_nodes(new_graph) == 100
    @test num_local_nodes(new_graph) == 0

    # test `apply_partition!` and modify original graph
    apply_partition!(graph, partition)
    @test num_local_nodes(graph) == 0
    @test num_nodes(graph) == 100

    @objective(graph, Min, sum(all_variables(graph)))
    set_optimizer(graph, optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0))
    optimize!(graph)

    @test objective_value(graph) == obj_val
end

function test_node_vector_partition()
    graph = _create_simple_optigraph()
    node_membership_vector = [0, 0, 1, 1]
    partition = Partition(graph, node_membership_vector)
    new_graph = assemble_optigraph(partition)
    @test num_nodes(new_graph) == 4
end

# hypergraph
function test_partition_hypergraph()
    graph = _create_simple_optigraph()
    projection = hyper_projection(graph)
    partition_vector = @suppress KaHyPar.partition(projection, 2; configuration=kahypar_config)
    partition = Partition(projection, partition_vector)
    new_graph = assemble_optigraph(partition)
    @test num_nodes(new_graph) == 4
    @test num_subgraphs(new_graph) == 2
end

# #Edge-HyperGraph
# function test_partition_edge_hypergraph()
#     optigraph = _create_optigraph()
#     edge_hg, ref_map = edge_hyper_graph(optigraph)
#     partition_vector = @suppress KaHyPar.partition(edge_hg, 2; configuration=kahypar_config)
#     partition = Partition(partition_vector, ref_map)
#     return apply_partition!(optigraph, partition)

#     #TODO: new test for hierarchical
#     #@test graph_structure(optigraph) == Plasmo.RECURSIVE_TREE
# end

# #Bipartite Graph
# function test_bipartite_1()
#     optigraph = _create_optigraph()
#     bg, b_map = Plasmo.bipartite_graph(optigraph)
#     partition_vector = @suppress KaHyPar.partition(bg, 2; configuration=kahypar_config)
#     partition_bipartite = Partition(partition_vector, b_map)
#     return apply_partition!(optigraph, partition_bipartite)

#     #TODO new test
#     #@test graph_structure(optigraph) in [Plasmo.RECURSIVE_TREE,Plasmo.RECURSIVE_GRAPH,Plasmo.RECURSIVE_LINKED_TREE]

#     #TODO
#     #partition_bipartite = Partition(bg,partition_vector,b_map;cut_selector = :vertex)
#     #partition_bipartite = Partition(bg,partition_vector,b_map;cut_selector = :edge)
# end

# #Clique Graph
# function test_clique_graph()
#     optigraph = _create_optigraph()
#     cgraph, ref_map = clique_graph(optigraph)
#     partition_vector = @suppress KaHyPar.partition(cgraph, 2; configuration=kahypar_config)
#     partition = Partition(partition_vector, ref_map)
#     return apply_partition!(optigraph, partition)
#     #@test graph_structure(optigraph) == Plasmo.RECURSIVE_GRAPH
# end

# #Edge-CliqueGraph
# function test_edge_clique_graph()
#     optigraph = _create_optigraph()
#     edgegraph, ref_map = edge_graph(optigraph)
#     part_vector = @suppress KaHyPar.partition(edgegraph, 2; configuration=kahypar_config)
#     partition = Partition(part_vector, ref_map)
#     return apply_partition!(optigraph, partition)
#     #@test graph_structure(optigraph) == Plasmo.RECURSIVE_TREE
#     #TODO: new test. should be has_hierarhical_edges
# end

# #Specialized partition functions
# function test_partition_to()
#     graph = _create_chain_optigraph()
#     pfunc = KaHyPar.partition

#     @suppress Plasmo.partition_to_subgraphs!(graph, pfunc, 8; configuration=kahypar_config)

#     @suppress Plasmo.partition_to_tree!(graph, pfunc, 8; configuration=kahypar_config)

#     @suppress Plasmo.partition_to_subgraph_tree!(
#         graph, pfunc, 8; configuration=kahypar_config
#     )
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

TestPartition.run_tests()

module TestGraphFunctions

using Plasmo
using LightGraphs: LightGraphs
using Test

# function _create_test_optigraph()
#     graph = OptiGraph()
#     @optinode(graph, nodes[1:100])
#     for node in nodes
#         @variable(node, 0 <= x <= 2)
#         @variable(node, 0 <= y <= 3)
#         @NLconstraint(node, x^3 + y <= 4)
#     end
#     @linkconstraint(graph, links[i=1:99], nodes[i][:x] == nodes[i + 1][:x])
#     @objective(graph, Min, sum(node[:y] for node in nodes))
#     return graph
# end

# function _create_test_optigraph_w_subgraphs()
#     graph = _create_test_optigraph()
#     node_vectors = [
#         graph.optinodes[1:20],
#         graph.optinodes[21:40],
#         graph.optinodes[41:60],
#         graph.optinodes[61:80],
#         graph.optinodes[81:100],
#     ]
#     partition = Partition(graph, node_vectors)
#     apply_partition!(graph, partition)
#     return graph
# end

# function test_hypergraph_backend()
#     graph = _create_test_optigraph()

#     Plasmo.set_graph_backend(graph)
#     @test isa(Plasmo.graph_backend(graph), Plasmo.HyperGraphBackend)

#     hgraph, proj_map = Plasmo.graph_backend_data(graph)
#     @test LightGraphs.nv(hgraph) == 100

#     #this should not reset the graph backend
#     @test Plasmo._init_graph_backend(graph) == false

#     graph = _create_test_optigraph()
#     #this will reset because it is empty
#     @test Plasmo.graph_backend(graph) == nothing
#     @test Plasmo._init_graph_backend(graph) == true
#     @test isa(Plasmo.graph_backend(graph), Plasmo.HyperGraphBackend)
# end

# function test_hypergraph_functions()
#     graph = _create_test_optigraph()

#     n1 = optinode(graph, 1)
#     n2 = optinode(graph, 2)
#     n3 = optinode(graph, 3)

#     @test LightGraphs.all_neighbors(graph, n1) == [n2]
#     @test LightGraphs.all_neighbors(graph, n2) == [n1, n3]

#     #3 nodes and 2 edges
#     induced1 = LightGraphs.induced_subgraph(graph, [n1, n2, n3])
#     @test num_all_nodes(induced1) == 3
#     @test num_all_edges(induced1) == 2

#     #2 nodes and no edges
#     induced2 = LightGraphs.induced_subgraph(graph, [n1, n3])
#     @test num_all_nodes(induced2) == 2
#     @test num_all_edges(induced2) == 0

#     e1 = optiedge(graph, 1)
#     e2 = optiedge(graph, 2)
#     incident_es1 = incident_edges(graph, n2)
#     @test incident_es1 == [e1, e2]

#     incident_es2 = incident_edges(graph, [n1, n2, n3])
#     n4 = optinode(graph, 4)
#     e3 = optiedge(graph, n3, n4)
#     @test length(incident_es2) == 1
#     @test incident_es2[1] == e3

#     induced_es = induced_edges(graph, [n1, n2, n3])
#     @test induced_es == [e1, e2]

#     neigh = Plasmo.neighborhood(graph, [n2, n3], 1)
#     @test Set(neigh) == Set([n1, n2, n3, n4])
# end

# function test_subgraph_functions()
#     graph = _create_test_optigraph_w_subgraphs()
#     sub1 = subgraph(graph, 1)
#     @test num_all_nodes(sub1) == 20

#     ex_sub1 = expand(graph, sub1, 1)
#     @test num_all_nodes(ex_sub1) == 21

#     ex_sub2 = expand(graph, sub1, 10)
#     @test num_all_nodes(ex_sub2) == 30

#     @test length(Plasmo.cross_edges(graph)) == 4

#     main_node = add_node!(graph)
#     @variable(main_node, z >= 0)
#     @linkconstraint(graph, main_node[:z] == optinode(sub1, 1)[:x])

#     @test length(Plasmo.hierarchical_edges(graph)) == 1
#     @test length(Plasmo.cross_edges(graph)) == 4
#     @test num_linkconstraints(graph) == 5
# end

# function test_partition_functions()
#     graph = _create_test_optigraph()
#     node_vectors = [
#         graph.optinodes[1:20],
#         graph.optinodes[21:40],
#         graph.optinodes[41:60],
#         graph.optinodes[61:80],
#         graph.optinodes[81:100],
#     ]

#     identified_edges = Plasmo.identify_edges(graph, node_vectors)
#     @test length(identified_edges[1]) == 5 #5 partitions
#     @test length(identified_edges[2]) == 4 #4 linking edges

#     edge_vectors = [
#         graph.optiedges[1:20],
#         graph.optiedges[21:40],
#         graph.optiedges[41:60],
#         graph.optiedges[61:80],
#         graph.optiedges[81:99],
#     ]
#     identified_nodes = Plasmo.identify_nodes(graph, edge_vectors)
#     @test length(identified_nodes[1]) == 5
#     @test length(identified_nodes[2]) == 4
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

TestGraphFunctions.run_tests()

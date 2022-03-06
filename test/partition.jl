module TestPartition

using Plasmo
using KaHyPar
using Test

kahypar_configuration = (@__DIR__)*"/cut_kKaHyPar_sea20.ini"

function _create_optigraph()
    optigraph = OptiGraph()
    @optinode(optigraph,nodes[1:4])

    #node 1
    @variable(nodes[1],0 <= x <= 2)
    @variable(nodes[1],0 <= y <= 3)
    @constraint(nodes[1],0 <= x+y <= 4)
    @objective(nodes[1],Min,x)

    #node 2
    @variable(nodes[2],x >= 1)
    @variable(nodes[2],0 <= y <= 5)
    @NLconstraint(nodes[2],exp(x)+y <= 7)
    @objective(nodes[2],Min,x)

    #node 3
    @variable(nodes[3],x >= 0)
    @variable(nodes[3],y >= 0)
    @constraint(nodes[3],x + y == 2)
    @objective(nodes[3],Max,x)

    #node 4
    @variable(nodes[4],0 <= x <= 1)
    @variable(nodes[4],y >= 0)
    @constraint(nodes[4],x + y <= 3)
    @objective(nodes[4],Max,y)

    #Link constraints take the same expressions as the JuMP @constraint macro
    @linkconstraint(optigraph,nodes[1][:x] == nodes[2][:x])
    @linkconstraint(optigraph,nodes[2][:y] == nodes[3][:x])
    @linkconstraint(optigraph,nodes[3][:x] == nodes[4][:x])

    return optigraph
end

function test_partition_manual()
    graph = OptiGraph()
    @optinode(graph,nodes[1:100])
    for node in nodes
        @variable(node,x >= 0)
    end
    for j = 1:99
        @linkconstraint(graph,nodes[j][:x] == nodes[j+1][:x])
    end
    A = reshape(nodes,20,5)
    node_vectors = [A[c,:] for c in 1:size(A,1)]
    partition = Partition(graph,node_vectors)
    @test length(partition.subpartitions) == 20
    @test num_nodes(graph) == 100
    apply_partition!(graph,partition)
    @test num_nodes(graph) == 0
    @test num_all_nodes(graph) == 100
end

#Hypergraph
function test_partition_hypergraph()
    optigraph = _create_optigraph()
    hg,hyper_map = Plasmo.hyper_graph(optigraph)
    partition_vector = KaHyPar.partition(hg,2;configuration = kahypar_configuration)
    partition_hyper = Partition(partition_vector,hyper_map)
    apply_partition!(optigraph,partition_hyper)
    @test graph_structure(optigraph) ==  Plasmo.RECURSIVE_GRAPH
end

#Edge-HyperGraph
function test_partition_edge_hypergraph()
    optigraph = _create_optigraph()
    edge_hg,ref_map = edge_hyper_graph(optigraph)
    partition_vector = KaHyPar.partition(edge_hg,2;configuration = kahypar_configuration)
    partition = Partition(partition_vector,ref_map)
    apply_partition!(optigraph,partition)
    @test graph_structure(optigraph) == Plasmo.RECURSIVE_TREE
end

#Bipartite Graph
function test_bipartite_1()
    optigraph = _create_optigraph()
    bg,b_map = Plasmo.bipartite_graph(optigraph)
    partition_vector = KaHyPar.partition(bg,2;configuration = kahypar_configuration)
    partition_bipartite = Partition(partition_vector,b_map)
    apply_partition!(optigraph,partition_bipartite)
    @test graph_structure(optigraph) in [Plasmo.RECURSIVE_TREE,Plasmo.RECURSIVE_GRAPH,Plasmo.RECURSIVE_LINKED_TREE]

    #TODO
    #partition_bipartite = Partition(bg,partition_vector,b_map;cut_selector = :vertex)
    #partition_bipartite = Partition(bg,partition_vector,b_map;cut_selector = :edge)
end

#Clique Graph
function test_clique_graph()
    optigraph = _create_optigraph()
    cgraph,ref_map = clique_graph(optigraph)
    partition_vector = KaHyPar.partition(cgraph,2;configuration = kahypar_configuration)
    partition = Partition(partition_vector,ref_map)
    apply_partition!(optigraph,partition)
    @test graph_structure(optigraph) == Plasmo.RECURSIVE_GRAPH
end

#Edge-CliqueGraph
function test_edge_clique_graph()
    optigraph = _create_optigraph()
    edgegraph,ref_map = edge_graph(optigraph)
    partition_vector = KaHyPar.partition(edgegraph,2;configuration = kahypar_configuration)
    partition = Partition(partition_vector,ref_map)
    apply_partition!(optigraph,partition)
    @test graph_structure(optigraph) == Plasmo.RECURSIVE_TREE
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

TestPartition.run_tests()

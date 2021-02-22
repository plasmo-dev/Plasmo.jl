module TestPartition

using Plasmo
using Test

function test_partition1()
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

    make_subgraphs!(graph,partition)

    @test num_nodes(graph) == 0
    @test num_all_nodes(graph) == 100
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

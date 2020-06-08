using Plasmo
using Test

mg = OptiGraph()

@optinode(mg,nodes[1:100])
for node in nodes
    @variable(node,x>=0)
end

for j = 1:99
    @linkconstraint(mg,nodes[j][:x] == nodes[j+1][:x])
end

A = reshape(nodes,20,5)
node_vectors = [A[c,:] for c in 1:size(A,1)]

partition = Partition(mg,node_vectors)

@test length(partition.subpartitions) == 20

@test num_nodes(mg) == 100

make_subgraphs!(mg,partition)

@test num_nodes(mg) == 0
@test length(all_nodes(mg)) == 100

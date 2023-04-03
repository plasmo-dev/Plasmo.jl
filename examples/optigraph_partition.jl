using Plasmo
using Ipopt
using KaHyPar

function create_optigraph()
    optigraph = OptiGraph()
    @optinode(optigraph, nodes[1:4])

    #node 1
    @variable(nodes[1], 0 <= x <= 2)
    @variable(nodes[1], 0 <= y <= 3)
    @constraint(nodes[1], 0 <= x + y <= 4)
    @objective(nodes[1], Min, x)

    #node 2
    @variable(nodes[2], x >= 1)
    @variable(nodes[2], 0 <= y <= 5)
    @NLconstraint(nodes[2], exp(x) + y <= 7)
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

    #Link constraints take the same expressions as the JuMP @constraint macro
    @linkconstraint(optigraph, nodes[1][:x] == nodes[2][:x])
    @linkconstraint(optigraph, nodes[2][:y] == nodes[3][:x])
    @linkconstraint(optigraph, nodes[3][:x] == nodes[4][:x])

    return optigraph
end

optigraph = create_optigraph()
set_optimizer(optigraph, Ipopt.Optimizer)
optimize!(optigraph)

#Partition nodes manually
optigraph = create_optigraph()
nodes = all_nodes(optigraph)
node_vectors = [[nodes[1], nodes[2]], [nodes[3], nodes[4]]]
partition = Partition(optigraph, node_vectors)
apply_partition!(optigraph, partition)
set_optimizer(optigraph, Ipopt.Optimizer)
optimize!(optigraph)

#Partition edges manually
optigraph = create_optigraph()
es = all_edges(optigraph)
edge_vectors = [[es[1], es[2]], [es[3]]]
partition = Partition(optigraph, edge_vectors)
apply_partition!(optigraph, partition)
set_optimizer(optigraph, Ipopt.Optimizer)
optimize!(optigraph)

#Partition with KaHyPar using different hypergraph representations

#Hypergraph
optigraph = create_optigraph()
hg, hyper_map = hyper_graph(optigraph)
partition_vector = KaHyPar.partition(hg, 2; configuration=:edge_cut)
partition = Partition(partition_vector, hyper_map)
apply_partition!(optigraph, partition)
set_optimizer(optigraph, Ipopt.Optimizer)
optimize!(optigraph)

#Edge-HyperGraph
# optigraph = create_optigraph()
edge_hg, ref_map = edge_hyper_graph(optigraph)
partition_vector = KaHyPar.partition(edge_hg, 2)
partition = Partition(partition_vector, ref_map)
apply_partition!(optigraph, partition)
optimize!(optigraph)

#Bipartite Graph
bg, b_map = Plasmo.bipartite_graph(optigraph)
partition_vector = KaHyPar.partition(bg, 2; configuration=:edge_cut)
partition_bipartite = Partition(partition_vector, b_map)
#Other cut selectors
#partition_bipartite = Partition(bg,partition_vector,b_map;cut_selector = :vertex)
#partition_bipartite = Partition(bg,partition_vector,b_map;cut_selector = :edge)
apply_partition!(optigraph, partition_bipartite)
optimize!(optigraph)

#Clique Graph
cgraph, ref_map = clique_graph(optigraph)
partition_vector = KaHyPar.partition(cgraph, 2)
partition = Partition(cgraph, partition_vector, ref_map)
apply_partition!(optigraph, partition)
optimize!(optigraph)

#Edge-CliqueGraph
edgegraph, ref_map = edge_graph(optigraph)
partition_vector = KaHyPar.partition(edgegraph, 2)
partition = Partition(edgegraph, partition_vector, ref_map)
apply_partition!(optigraph, partition)
optimize!(optigraph)

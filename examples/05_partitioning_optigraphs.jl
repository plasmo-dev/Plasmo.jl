using Plasmo
using Ipopt
using KaHyPar

function create_graph()
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
    @variable(nodes[3], x >= 1)
    @variable(nodes[3], y >= 0)
    @constraint(nodes[3], x + y == 2)

    #node 4
    @variable(nodes[4], 0 <= x <= 1)
    @variable(nodes[4], y >= 0)
    @constraint(nodes[4], x + y <= 3)

    # link constraints 
    @linkconstraint(graph, nodes[1][:x] == nodes[2][:x])
    @linkconstraint(graph, nodes[2][:y] == nodes[3][:x])
    @linkconstraint(graph, nodes[3][:x] == nodes[4][:x])

    return graph
end

# optimize the graph
graph = create_graph()
nodes = all_nodes(graph)
@objective(graph, Min, sum(node[:x] for node in nodes))
set_optimizer(graph, Ipopt.Optimizer)
optimize!(graph)

# partition nodes manually
graph = create_graph()
nodes = all_nodes(graph)
node_vectors = [[nodes[1], nodes[2]], [nodes[3], nodes[4]]]
partition = Partition(graph, node_vectors)
new_graph = assemble_optigraph(partition)
@objective(new_graph, Min, sum(node[:x] for node in nodes))
set_optimizer(new_graph, Ipopt.Optimizer)
optimize!(new_graph)

# partition edges manually
graph = create_graph()
nodes = all_nodes(graph)
es = all_edges(graph)
edge_vectors = [[es[1], es[2]], [es[3]]]
partition = Partition(graph, edge_vectors)
new_graph = assemble_optigraph(partition)
@objective(new_graph, Min, sum(node[:x] for node in nodes))
set_optimizer(new_graph, Ipopt.Optimizer)
optimize!(new_graph)

# Partition with KaHyPar using different hypergraph representations

# partition hypergraph projection
graph = create_graph()
nodes = all_nodes(graph)
projection = hyper_projection(graph)
partition_vector = KaHyPar.partition(projection, 2; configuration=:edge_cut)
partition = Partition(projection, partition_vector)
new_graph = assemble_optigraph(partition)
@objective(new_graph, Min, sum(node[:x] for node in nodes))
set_optimizer(new_graph, Ipopt.Optimizer)
optimize!(new_graph)

# clique-graph
graph = create_graph()
nodes = all_nodes(graph)
projection = clique_projection(graph)
partition_vector = KaHyPar.partition(projection, 2)
partition = Partition(projection, partition_vector)
new_graph = assemble_optigraph(partition)
@objective(new_graph, Min, sum(node[:x] for node in nodes))
set_optimizer(new_graph, Ipopt.Optimizer)
optimize!(new_graph)

# edge-hypergraph
graph = create_graph()
nodes = all_nodes(graph)
projection = edge_hyper_projection(graph)
partition_vector = KaHyPar.partition(projection, 2)
partition = Partition(projection, partition_vector)
new_graph = assemble_optigraph(partition)
@objective(new_graph, Min, sum(node[:x] for node in nodes))
set_optimizer(new_graph, Ipopt.Optimizer)
optimize!(new_graph)

# edge-clique-raph
graph = create_graph()
nodes = all_nodes(graph)
projection = edge_clique_projection(graph)
partition_vector = KaHyPar.partition(projection, 2)
partition = Partition(projection, partition_vector)
new_graph = assemble_optigraph(partition)
@objective(new_graph, Min, sum(node[:x] for node in nodes))
set_optimizer(new_graph, Ipopt.Optimizer)
optimize!(new_graph)

# bipartite-graph
graph = create_graph()
nodes = all_nodes(graph)
projection = bipartite_projection(graph)
partition_vector = KaHyPar.partition(projection, 2; configuration=:edge_cut)
partition = Partition(projection, partition_vector)
new_graph = assemble_optigraph(partition)
@objective(new_graph, Min, sum(node[:x] for node in nodes))
set_optimizer(new_graph, Ipopt.Optimizer)
optimize!(new_graph)

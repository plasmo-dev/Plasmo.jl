using Plasmo
using Graphs

function create_optigraph(name)
    graph = OptiGraph(;name=name)
    @optinode(graph, nodes[1:3])

    # node 1
    @variable(nodes[1], 0 <= x <= 2)
    @variable(nodes[1], 0 <= y <= 3)
    @constraint(nodes[1], x + y <= 4)
    @objective(nodes[1], Min, x)

    # node 2
    @variable(nodes[2], x >= 1)
    @variable(nodes[2], 0 <= y <= 5)
    @constraint(nodes[2], x + y <= 7)
    @objective(nodes[2], Min, x)

    # node 3
    @variable(nodes[3], x >= 0)
    @variable(nodes[3], y >= 0)
    @constraint(nodes[3], x + y == 2)
    @objective(nodes[3], Max, x)

    # link constraints
    @linkconstraint(graph, nodes[1][:x] == nodes[2][:x])
    @linkconstraint(graph, nodes[2][:y] == nodes[3][:x])
    @linkconstraint(graph, nodes[3][:x] == nodes[1][:x])
    @linkconstraint(graph, nodes[1][:y] + nodes[2][:y] + nodes[3][:y] == 3)

    return graph
end

graph = OptiGraph(;name=:graph)

graph1 = create_optigraph(:sg1)
graph2 = create_optigraph(:sg2)
graph3 = create_optigraph(:sg3)

add_subgraph!(graph, graph1)
add_subgraph!(graph, graph2)
add_subgraph!(graph, graph3)

# node from each subgraph
n1 = graph1[1]
n2 = graph2[1]
n3 = graph3[1]

# link subgraphs
@linkconstraint(graph, n1[:x] + n2[:x] + n3[:x] == 5)

# incident edges
incident_edges(graph, n1)                # incident to node
incident_edges(graph, all_nodes(graph1)) # incident to graph

# neighbors
all_neighbors(graph1, n1)       # local
all_neighbors(graph, n1) # global

# induced optigraph
induced_graph = induced_subgraph(graph, [n1, n2, n3])
@objective(induced_graph, Min, sum(all_variables(induced_graph)))
set_optimizer(induced_graph, HiGHS.Optimizer)
optimize!(induced_graph)

# expanded optigraph
expanded_graph = expand(graph, graph1, 1)
@objective(expanded_graph, Min, sum(all_variables(expanded_graph)))
set_optimizer(expanded_graph, HiGHS.Optimizer)
optimize!(expanded_graph)

# nodes store solution for each graph
value(induced_graph, n1[:x])
value(expanded_graph, n1[:x])
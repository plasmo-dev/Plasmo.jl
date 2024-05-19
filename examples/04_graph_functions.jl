using Plasmo
using Graphs
using HiGHS

function create_optigraph(name)
    graph = OptiGraph(;name=name)
    @optinode(graph, nodes[1:3])

    # node 1
    @variable(nodes[1], 0 <= x <= 2)
    @variable(nodes[1], 0 <= y <= 3)
    @constraint(nodes[1], x + y <= 4)
    # @objective(nodes[1], Min, x)

    # node 2
    @variable(nodes[2], x >= 1)
    @variable(nodes[2], 0 <= y <= 5)
    @constraint(nodes[2], x + y <= 7)
    # @objective(nodes[2], Min, x)

    # node 3
    @variable(nodes[3], x >= 0)
    @variable(nodes[3], y >= 0)
    @constraint(nodes[3], x + y == 2)
    # @objective(nodes[3], Max, x)

    # link constraints
    @linkconstraint(graph, nodes[1][:x] == nodes[2][:x])
    @linkconstraint(graph, nodes[2][:y] == nodes[3][:x])
    @linkconstraint(graph, nodes[3][:x] == nodes[1][:x])
    @linkconstraint(graph, nodes[1][:y] + nodes[2][:y] + nodes[3][:y] == 3)

    return graph
end

### create optigraph

graph = OptiGraph(;name=:graph)

graph1 = create_optigraph(:sg1)
graph2 = create_optigraph(:sg2)
graph3 = create_optigraph(:sg3)

add_subgraph(graph, graph1)
add_subgraph(graph, graph2)
add_subgraph(graph, graph3)

# node from each subgraph
n1 = graph1[1]
n2 = graph2[1]
n3 = graph3[1]

# link subgraphs
@linkconstraint(graph, n1[:x] + n2[:x] + n3[:x] == 5)


### query topology

# create a hypergraph projection from the top-level graph
projection = hyper_projection(graph)

# query incident edges to node `n1` using the projection
incident_edges(projection, n1)

# query incident edges to all of the nodes in `graph1`
incident_edges(projection, all_nodes(graph1))

# query the neighbors to `n1` in `graph`
all_neighbors(projection, n1)

# query the neighbors to `n1` in `graph1`
subproj1 = hyper_projection(graph1)
all_neighbors(subproj1, n1)          

# create an induced subgraph from a given set of nodes
induced_graph = induced_subgraph(projection, [n1, n2, n3])
@objective(induced_graph, Min, sum(all_variables(induced_graph)))
set_optimizer(induced_graph, HiGHS.Optimizer)
optimize!(induced_graph)

# create an expanded graph
expanded_graph = expand(projection, graph1, 1)
@objective(expanded_graph, Min, sum(all_variables(expanded_graph)))
set_optimizer(expanded_graph, HiGHS.Optimizer)
optimize!(expanded_graph)

# nodes store solution for each graph
println("value(induced_graph, n1[:x]): ", value(induced_graph, n1[:x]))
println("value(expanded_graph, n1[:x]) ", value(expanded_graph, n1[:x]))
using Plasmo
using Ipopt

function add_model(graph::OptiGraph)
    node = add_node(graph)
    @variable(node, x >= 0)
    @variable(node, y >= 1)
    @constraint(node, x + y <= 5)
    @constraint(node, exp(x) >= 2)
    return node
end

# the top-level graph
graph = OptiGraph(; name=:my_graph)

# subgraph 1
subgraph1 = OptiGraph(; name=:sg1)
n1 = add_model(subgraph1)
n2 = add_model(subgraph1)
@linkconstraint(subgraph1, n1[:x] == n2[:x])

# subgraph 2
subgraph2 = OptiGraph(; name=:sg2)
n3 = add_model(subgraph2)
n4 = add_model(subgraph2)
@linkconstraint(subgraph2, n3[:x] == n4[:x])

# add subgraphs to top-level graph
add_subgraph(graph, subgraph1)
add_subgraph(graph, subgraph2)

# add links between subgraphs
@linkconstraint(graph, n1[:x] == n3[:x])
@linkconstraint(graph, n2[:x] == n4[:x])

# objective function
@objective(graph, Min, sum(node[:x] + node[:y] for node in all_nodes(graph)))

set_optimizer(graph, Ipopt.Optimizer)
optimize!(graph)

println("n1[:x]= ", value(graph, n1[:x]))
println("n2[:x]= ", value(graph, n2[:x]))
println("n3[:x]= ", value(graph, n3[:x]))
println("n4[:x]= ", value(graph, n4[:x]))

println("objective = ", objective_value(graph))

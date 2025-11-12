#Example
using Plasmo
using HiGHS

# create optigraph; set optimizer
graph = OptiGraph()
optimizer = HiGHS.Optimizer

# add nodes using macro
@optinode(graph, n1)
@optinode(graph, n2)

# node 1 model
@variable(n1, 1 <= x <= 2)
@variable(n1, 0 <= y <= 3)
@variable(n1, z >= 0)
@constraint(n1, x + y + z >= 4)

# node 2 model
@variable(n2, x)
@variable(n2, z >= 0)
@constraint(n2, z + x >= 4)

# add link constraints
@linkconstraint(graph, n1[:x] == n2[:x])
@linkconstraint(graph, n1[:z] == n2[:z])

# add objective function
@objective(graph, Min, n1[:y] + n2[:x] + n1[:z])

# aggregate optinodes into a single optinode
aggregate_node, reference_map = aggregate(graph)
agg_graph = source_graph(aggregate_node)
set_optimizer(agg_graph, optimizer)
optimize!(agg_graph)

# use the reference map to look up values on the aggregate node
println("n1[:x] = ", value(reference_map[n1[:x]]))
println("n2[:x] = ", value(reference_map[n2[:x]]))
println("n1[:z] = ", value(reference_map[n1[:z]]))

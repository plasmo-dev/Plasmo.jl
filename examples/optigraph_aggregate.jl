#Example
using Plasmo
using GLPK

#Create a modelgraph
graph = OptiGraph()
optimizer = GLPK.Optimizer

#Add nodes to optigraph
n1 = @optinode(graph)
n2 = @optinode(graph)

#Node 1 Model
@variable(n1, 0 <= x <= 2)
@variable(n1, 0 <= y <= 3)
@variable(n1, z >= 0)
@constraint(n1, x + y + z >= 4)

#Node 2 Model
@variable(n2, x)
@variable(n2, z >= 0)
@constraint(n2, z + x >= 4)

#Link constraints take the same expressions as the JuMP @constraint macro
@linkconstraint(graph, n1[:x] == n2[:x])
@linkconstraint(graph, n1[:z] == n2[:z])

#Objective function
@objective(graph, Min, n1[:y] + n2[:x] + n1[:z])

#Aggregate optinodes into a single optinode to solve using JuMP's interface
aggregate_node, reference_map = aggregate(graph)
set_optimizer(aggregate_node, optimizer)
optimize!(aggregate_node)

#Use the reference map to look up values on the aggregate node
println("n1[:x] = ", value(reference_map[n1[:x]]))
println("n2[:x] = ", value(reference_map[n2[:x]]))

#Example depicting how to combine the nodes in a modelgraph and reference the original modelgraph
using Plasmo
using Ipopt

#Create a modelgraph
graph = OptiGraph()
optimizer = Ipopt.Optimizer

#Node 1 model
n1 = @optinode(graph)
@variable(n1,0 <= x <= 2)
@variable(n1,0 <= y <= 3)
@constraint(n1,x+y <= 4)
@objective(n1,Min,2*x)

#Node 2 model
n2 = @optinode(graph)
@variable(n2,x)
@NLconstraint(n2,exp(x) >= 2)

#Link constraints take the same expressions as the JuMP @constraint macro
@linkconstraint(graph,n1[:x] == n2[:x])

#Combine modelnodes until a single node
aggregate_node,reference_map = aggregate(graph)
set_optimizer(aggregate_node,optimizer)
optimize!(aggregate_node)

#Use the reference map to look up values
println("n1[:x] = ",value(reference_map[n1[:x]]))
println("n2[:x] = ",value(reference_map[n2[:x]]))

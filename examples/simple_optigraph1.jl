using Plasmo
using Ipopt

graph = OptiGraph()
optimizer = Ipopt.Optimizer

#Add nodes to a ModelGraph
n1 = @optinode(graph)
n2 = @optinode(graph)

#Node 1 Model
@variable(n1,0 <= x <= 2)
@variable(n1,0 <= y <= 3)
@variable(n1, z >= 0)
@constraint(n1,x+y+z >= 4)

#Node 2 Model
@variable(n2,x)
@NLnodeconstraint(n2,ref,exp(x) >= 2)
@variable(n2,z >= 0)
@constraint(n2,z + x >= 4)

#Link constraints take the same expressions as the JuMP @constraint macro
@linkconstraint(graph,n1[:x] == n2[:x])
@linkconstraint(graph,n1[:z] == n2[:z])

#Graph objective
@objective(graph,Min,n1[:y] + n2[:x] + n1[:z])

#Optimize with Ipopt.
optimize!(graph,optimizer)

println("n1[:z]= ",value(n1,n1[:z]))
println("n2[:z]= ",value(n2,n2[:z]))
println("n1[:x]= ",value(n1,n1[:x]))
println("n1[:y]= ",value(n1,n1[:y]))
println("n2[:x]= ",value(n2,n2[:x]))
println("objective = ", objective_value(graph))

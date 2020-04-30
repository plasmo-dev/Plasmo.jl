using Plasmo
using Ipopt
using JuMP

graph = ModelGraph()
optimizer = Ipopt.Optimizer

#Add nodes to a GraphModel
n1 = @node(graph)
n2 = @node(graph)

m1 = JuMP.Model()
JuMP.@variable(m1,0 <= x <= 2)
JuMP.@variable(m1,0 <= y <= 3)
JuMP.@constraint(m1,x+y <= 4)
JuMP.@objective(m1,Min,x)

m2 = JuMP.Model()
JuMP.@variable(m2,x)
JuMP.@NLconstraint(m2,ref,exp(x) >= 2)

#Set models on nodes and edges
set_model(n1,m1)     #set m1 to node 1.  Updates reference on m1
set_model(n2,m2)

#Link constraints take the same expressions as the JuMP @constraint macro
@linkconstraint(graph,n1[:x] == n2[:x])

optimize!(graph,optimizer)

println("n1[:x]= ",value(n1,n1[:x]))
println("n2[:x]= ",value(n2,n2[:x]))
println("objective = ", objective_value(graph))

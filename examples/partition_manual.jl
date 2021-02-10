using Plasmo
using Ipopt


optigraph = OptiGraph()

#Add nodes to a GraphModel
@optinode optigraph n1
@optinode optigraph n2
@optinode optigraph n3
@optinode optigraph n4

#Set a model on node 1
@variable(n1,0 <= x <= 2)
@variable(n1,0 <= y <= 3)
@constraint(n1,x+y <= 4)
@objective(n1,Min,x)

@variable(n2,x >= 1)
@variable(n2,0 <= y <= 5)
@NLconstraint(n2,exp(x)+y <= 7)
@objective(n2,Min,x)

@variable(n3,x >= 0)

@variable(n4,0 <= x <= 1)

ipopt = Ipopt.Optimizer

#Link constraints take the same expressions as the JuMP @constraint macro
@linkconstraint(optigraph,n1[:x] == n2[:x])
@linkconstraint(optigraph,n2[:y] == n3[:x])
@linkconstraint(optigraph,n3[:x] == n4[:x])

optimize!(optigraph,ipopt)

node_vectors = [[n1,n2],[n3,n4]]
partition = Partition(optigraph,node_vectors)
make_subgraphs!(optigraph,partition)
new_optigraph,ref_map = combine(optigraph,0)

optimize!(new_optigraph,ipopt)

#Check results
println()
println("Combined Entire Graph Solution")
println("n1[:x]= ",nodevalue(n1[:x]))
println("n1[:y]= ",nodevalue(n1[:y]))

println("n2[:x]= ",nodevalue(n2[:x]))
println("n2[:y]= ",nodevalue(n2[:y]))

println("n3[:x]= ",nodevalue(n3[:x]))
println("n4[:x]= ",nodevalue(n4[:x]))

println()
println("Aggregated Partitioned Graph Solution (solution should be the same)")
println("")
println("n1[:x]= ",nodevalue(ref_map[n1[:x]]))
println("n1[:y]= ",nodevalue(ref_map[n1[:y]]))

println("n2[:x]= ",nodevalue(ref_map[n2[:x]]))
println("n2[:y]= ",nodevalue(ref_map[n2[:y]]))

println("n3[:x]= ",nodevalue(ref_map[n3[:x]]))
println("n4[:x]= ",nodevalue(ref_map[n4[:x]]))

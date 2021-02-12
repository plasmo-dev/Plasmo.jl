using Plasmo
using Ipopt

graph = OptiGraph()
optimizer = Ipopt.Optimizer
set_optimizer(graph,optimizer)

#Add nodes to a OptiGraph
@optinode(graph,nodes[1:4])

@variable(nodes[1],0 <= x <= 2)
@variable(nodes[1],0 <= y <= 3)
@variable(nodes[1], z >= 0)
@constraint(nodes[1],x+y+z >= 4)
@objective(nodes[1],Min,y)

@variable(nodes[2],x >= 0)
@NLconstraint(nodes[2],ref,exp(x) >= 2)
@variable(nodes[2],z >= 0)
@constraint(nodes[2],z + x >= 4)
@objective(nodes[2],Min,x)

@variable(nodes[3],x[1:3] >= 0)
@NLconstraint(nodes[3],nlcon,exp(x[3]) >= 5)
@constraint(nodes[3],conref,sum(x[i] for i = 1:3) == 10)
@objective(nodes[3],Max,x[1] + x[2] + x[3])

@variable(nodes[4],x[1:2] >= 0)
@constraint(nodes[4],sum(x[i] for i = 1:2) >= 10)
@NLconstraint(nodes[4],ref,exp(x[2]) >= 4)
@NLobjective(nodes[4],Min,x[2]^3)

#Link constraints take the same expressions as the JuMP @constraint macro
@linkconstraint(graph,nodes[1][:x] == nodes[2][:x])
@linkconstraint(graph,nodes[2][:x] == nodes[3][:x][3])
@linkconstraint(graph,nodes[3][:x][1] == nodes[4][:x][1])

optimize!(graph)


println("objective value = ", objective_value(graph))
println()
println("variable values:")
for var in all_variables(graph)
    println(var," = ",value(var))
end
println()
println("dual values:")
println(conref," = ",dual(conref))
println(nlcon," = ",dual(nlcon))
# #TODO
# println("dual values:")
# for con_type in list_of_constraint_types(graph)
# end

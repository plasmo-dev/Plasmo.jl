using Plasmo
using Ipopt

graph = OptiGraph(;name=:graph)

# add nodes to a OptiGraph
n1 = add_node(graph)
@variable(n1, 0 <= x <= 2)
@variable(n1, 0 <= y <= 3)
@variable(n1, 0 <= z <= 2)
@constraint(n1, x + y + z >= 4)

n2 = add_node(graph)
@variable(n2, x >= 0)
@constraint(n2, ref, exp(x) >= 2)
@variable(n2, 0 <= z <= 2)
@constraint(n2, z + x >= 4)

n3 = add_node(graph)
@variable(n3, x[1:3] >= 0)
@constraint(n3, nlcon, exp(x[3]) >= 5)
@constraint(n3, conref, sum(x[i] for i in 1:3) == 10)

n4 = add_node(graph)
@variable(n4, x[1:2] >= 0)
@constraint(n4, sum(x[i] for i in 1:2) >= 10)
@constraint(n4, ref, exp(x[2]) >= 4)

# add link constsraints
@linkconstraint(graph, link1, n1[:x] == n2[:x])
@linkconstraint(graph, link2, n2[:x] == n3[:x][3])
@linkconstraint(graph, link3, n3[:x][1] == n4[:x][1])

# set an objective for the graph
@objective(graph, Min, n1[:y] + n2[:x] - (n3[:x][1] + n3[:x][2] + n3[:x][3]) + n4[:x][2]^3)

# optimize the graph
optimizer = Ipopt.Optimizer
set_optimizer(graph, optimizer)
optimize!(graph)

println()
println("objective value = ", objective_value(graph))
println()

println("variable values:")
for var in all_variables(graph)
    println(var, " = ", value(var))
end
println()

println("constraint dual values:")
for constraint_type in list_of_constraint_types(graph)
    cons = all_constraints(graph, constraint_type[1], constraint_type[2])
    for con in cons
        println("($con) = $(dual(con))")
    end
end
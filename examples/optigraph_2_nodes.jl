using Plasmo
using GLPK

graph = OptiGraph()

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

#Optimize with glpk.
optimizer = GLPK.Optimizer
set_optimizer(graph, optimizer)
optimize!(graph)

#Get results
println()
println("objective value = ", objective_value(graph))

println()
println("variable values:")
println("n1[:z] = ", value(n1[:z]))
println("n2[:z] = ", value(n2[:z]))
println("n1[:x] = ", value(n1[:x]))
println("n1[:y] = ", value(n1[:y]))
println("n2[:x] = ", value(n2[:x]))

println()
println("dual values on nodes:")
for constraint_type in list_of_constraint_types(graph)
    cons = all_constraints(graph, constraint_type[1], constraint_type[2])
    for con in cons
        println("($con) = $(dual(con))")
    end
end

println()
println("dual values on link constraints")
for link in all_linkconstraints(graph)
    println("($link) = $(dual(link))")
end

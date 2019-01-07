using Plasmo
using JuMP
using Ipopt
#using MPI

#MPI.Init()
graph = Plasmo.ModelGraph()
m = Model()
master_node = add_node(graph,m)
@variable(m, x0[1:2], start=1)
@constraint(m, 0<=x0[1] + x0[2] <= 100)
@objective(m, Min, x0[1]^2 + x0[2]^2 + x0[1]*x0[2])

NS = 2
child_nodes = Array{Plasmo.ModelNode}(undef,NS)
for i in 1:NS
   bl = Model()
   @variable(bl, x[1:2], start=1)
   @NLobjective(bl, Min, x[1]^2 + x[2]^2 + x[1]*x[2])
   child_node = add_node(graph,bl)
   child_nodes[i] = child_node

   if i==1
       @linkconstraint(graph,   x0[2] + x[1] + x[2] <= 500)
       @linkconstraint(graph,   x0[2] + x[1] + x[2] >= 0)
       @linkconstraint(graph,0 <= x0[2] + x[1] + x[2] <= 500)
   end

   if i==2
       @linkconstraint(graph, x0[1] + x[1] + x[2] <= 500)
       @linkconstraint(graph, x0[1] + x[1] + x[2] >= 0)
   end
   #child_node = add_node(graph,bl)
   child_nodes[i] = child_node

end
setsolver(graph,Ipopt.IpoptSolver())
Plasmo.solve(graph)

true

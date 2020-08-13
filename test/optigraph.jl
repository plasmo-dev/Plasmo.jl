using Plasmo
using Test

graph = OptiGraph()
@optinode(graph,n1)
@optinode(graph,nodes[1:5])
@optinode(graph,nodes[1:3,1:3])

for node in all_nodes(graph)
    @variable(node,x>=0)
    @variable(node,y>=2)
    @constraint(node,x + y == 3)
    @objective(node,Min,y)
end

@linkconstraint(graph,n1[:x] == nodes[1][:x])
@linkconstraint(graph,sum(nodes[i][:x] for i = 1:5) == 5)

@test num_nodes(graph) == 15
@test num_optiedges(graph) == 2
@test num_linkconstraints(graph) == 2

true

using Plasmo
using Test

mg = ModelGraph()
@node(mg,n1)
@node(mg,nodes[1:5])
@node(mg,nodes[1:3,1:3])

for node in all_nodes(mg)
    @variable(node,x>=0)
    @variable(node,y>=2)
    @constraint(node,x + y == 3)
    @objective(node,Min,y)
end

@linkconstraint(mg,n1[:x] == nodes[1][:x])
@linkconstraint(mg,sum(nodes[i][:x] for i = 1:5) == 5)

@test num_nodes(mg) == 15
@test num_linkedges(mg) == 2
@test num_linkconstraints(mg) == 2

true

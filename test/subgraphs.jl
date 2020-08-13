using Plasmo

graph = OptiGraph()

@optinode(graph,n0)
@variable(n0,x)

sg1 = OptiGraph()
sg2 = OptiGraph()
add_subgraph!(graph,sg1)
add_subgraph!(graph,sg2)

@optinode(sg1,ng1[1:5])
@optinode(sg2,ng2[1:5])

for node in getnodes(sg1)
    @variable(node,0 <= x <= 2)
    @objective(node,Max,x)
end

for node in getnodes(sg2)
    @variable(node,x>=2)
    @objective(node,Min,x)
end

@linkconstraint(sg1,sum(ng1[i][:x] for i = 1:5) <= 4)
@linkconstraint(sg2,sum(ng2[i][:x] for i = 1:5) >= 4)

@linkconstraint(graph,n0[:x] == ng1[1][:x])
@linkconstraint(graph,n0[:x] == ng2[1][:x])

@test num_nodes(graph) == 1
@test length(all_nodes(graph)) == 11
@test num_optiedges(graph) == 2
@test num_all_optiedges(graph) == 4

true

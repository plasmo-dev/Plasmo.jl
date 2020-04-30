using Plasmo

mg = ModelGraph()

@node(mg,n0)
@variable(n0,x)

sg1 = ModelGraph()
sg2 = ModelGraph()
add_subgraph!(mg,sg1)
add_subgraph!(mg,sg2)

@node(sg1,ng1[1:5])
@node(sg2,ng2[1:5])

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

@linkconstraint(mg,n0[:x] == ng1[1][:x])
@linkconstraint(mg,n0[:x] == ng2[1][:x])

@assert num_nodes(mg) == 1
@assert length(all_nodes(mg)) == 11
@assert num_linkedges(mg) == 2
@assert num_all_linkedges(mg) == 4

true

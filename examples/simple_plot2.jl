using Plasmo
using Plots
#theme(:juno)

graph = OptiGraph()

@node(graph,node0)
@variable(node0,z[1:2])
@constraint(node0,z[1] + z[2] <= 2)

subgraph = OptiGraph()
add_subgraph!(graph,subgraph)

@node(subgraph,n1)
@node(subgraph,n2)

@variable(n1,0 <= x <= 2)
@variable(n1,0 <= y <= 3)
@variable(n1, z >= 0)
@constraint(n1,x+ y + z >= 4)


@variable(n2,x)
@NLnodeconstraint(n2,ref,exp(x) >= 2)
@variable(n2,z >= 0)
@constraint(n2,z + x >= 4)

@linkconstraint(subgraph,n1[:x] == n2[:x])

@linkconstraint(graph,node0[:z][1] == n1[:z])
@linkconstraint(graph,node0[:z][2] == n2[:z])

@objective(graph,Min,n1[:y] + n2[:x])


plt_graph = Plots.plot(graph,markersize = 20);
plt_matrix = Plots.spy(graph,node_labels = true);

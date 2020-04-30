using JuMP
using Plasmo
using Ipopt

function nl_model!(node::ModelNode)
    @variable(node,x >= rand())
    @variable(node,y >= 1)
    @constraint(node,x + y <= 5)
    @NLnodeconstraint(node,exp(x) >= 2)
    @objective(node,Min,x + y)
    return nothing
end

#the top level graph
graph = ModelGraph()

#System 1
subgraph1 = ModelGraph()
@node(subgraph1,n1)
@node(subgraph1,n2)
nl_model!(n1)
nl_model!(n2)
@linkconstraint(subgraph1,n1[:x] == n2[:x])  #linkconstraint is local to graph1

#System 2
subgraph2 = ModelGraph()
@node(subgraph2,n3)
@node(subgraph2,n4)
nl_model!(n3)
nl_model!(n4)
@linkconstraint(subgraph2,n3[:x] == n4[:x])

#Top level links
add_subgraph!(graph,subgraph1)
add_subgraph!(graph,subgraph2)
@linkconstraint(graph,n1[:x] == n3[:x])
@linkconstraint(graph,n1[:x] <= n3[:x])

optimize!(graph,Ipopt.Optimizer)

println("n1[:x]= ",value(n1,n1[:x]))
println("n2[:x]= ",value(n2,n2[:x]))
println("n3[:x]= ",value(n3,n3[:x]))
println("n4[:x]= ",value(n4,n4[:x]))

println("objective = ", objective_value(graph))

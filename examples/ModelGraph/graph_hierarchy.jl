using JuMP
using Plasmo
using Ipopt

function nl_model()
    m = Model()
    @variable(m,x >= 0)
    @variable(m,y >= 0)
    @constraint(m,x + y <= 5)
    @NLconstraint(m,exp(x) >= 2)
    @objective(m,Max,y)
    return m
end

#the top level graph
graph = ModelGraph()
setsolver(graph,Ipopt.IpoptSolver())

#System 1
graph1 = ModelGraph()
n1 = add_node(graph1,nl_model())
n2 = add_node(graph1,nl_model())
@linkconstraint(graph1,n1[:x] == n2[:x])  #linkconstraint is local to graph1

#System 2
graph2 = ModelGraph()
n3 = add_node(graph2,nl_model())
n4 = add_node(graph2,nl_model())
@linkconstraint(graph2,n3[:x] == n4[:x])

#Top level links
#check which link constraints I can get here (do I need a getalllinkconstraints function?)
add_subgraph(graph,graph1)
add_subgraph(graph,graph2)
@linkconstraint(graph,n1[:x] == n3[:x])

solve(graph)

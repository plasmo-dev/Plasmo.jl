using Plasmo

graph = ModelGraph()

@node(graph,n1)
@variable(n1,x[1:2] <= 2)
set_start_value(x[1],2)
set_start_value(x[2],1)
@NLnodeobjective(n1,Max,x[1]^2 + x[2]^2)

@node(graph,n2)
@variable(n2,x[1:2] >= 0 )
set_start_value(x[1],2)
set_start_value(x[2],2)
@NLnodeobjective(n2,Min,x[1]^3 + x[2]^2)

new_node,ref = combine(graph)


return true

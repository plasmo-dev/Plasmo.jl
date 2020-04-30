using Plasmo

graph = ModelGraph()

#Add nodes to a GraphModel
@node(graph,n1)
@node(graph,n2)
@node(graph,n3)
@node(graph,n4)

@variable(n1,0 <= x <= 2)
@variable(n1,0 <= y <= 3)
@NLnodeconstraint(n1,x^3+y <= 4)
@objective(n1,Min,x)

#Set a model on node 2

vals = collect(1:5)
grid = 1:3
@variable(n2,x >= 1)
@variable(n2,0 <= y <= 5)
@variable(n2,z[1:5] >= 0)
@variable(n2,a[vals,grid] >=0 )
@NLnodeconstraint(n2,exp(x)+y <= 7)
@objective(n2,Min,x)

@variable(n3,x[1:5])

@variable(n4,x <= 1)


#Link constraints take the same expressions as the JuMP @constraint macro
@linkconstraint(graph,n4[:x] == n1[:x])
@linkconstraint(graph,[t = 1:5],n4[:x] == n2[:z][t])
@linkconstraint(graph,[i = 1:5],n3[:x][i] == n1[:x])
@linkconstraint(graph,[j = 1:5,i = 1:3],n2[:a][j,i] == n4[:x])
@linkconstraint(graph,[i = 1:3],n1[:x] + n2[:z][i] + n3[:x][i] + n4[:x] >= 0)

# ipopt = Ipopt.Optimizer
# optimize!(graph,ipopt)
#
# #Query solution
# @assert nodevalue(n2[:x]) ≈ 1

true

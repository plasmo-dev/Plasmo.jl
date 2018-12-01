using JuMP
using Plasmo
using Ipopt

graph = Plasmo.ModelGraph()

setsolver(graph,Ipopt.IpoptSolver())

#Add nodes to a GraphModel
n1 = Plasmo.add_node(graph)
n2 = Plasmo.add_node(graph)
n3 = Plasmo.add_node(graph)
n4 = Plasmo.add_node(graph)
#Add edges between the nodes


#Set a model on node 1
m1 = JuMP.Model()
JuMP.@variable(m1,0 <= x <= 2)
JuMP.@variable(m1,0 <= y <= 3)
JuMP.@constraint(m1,x+y <= 4)
JuMP.@objective(m1,Min,x)

#Set a model on node 2
m2 = JuMP.Model()
vals = collect(1:5)
grid = 1:3
JuMP.@variable(m2,x >= 1)
JuMP.@variable(m2,0 <= y <= 5)
JuMP.@variable(m2,z[1:5] >= 0)
JuMP.@variable(m2,a[vals,grid] >=0 )
JuMP.@NLconstraint(m2,exp(x)+y <= 7)
JuMP.@objective(m2,Min,x)

m3 = JuMP.Model()
JuMP.@variable(m3,x[1:5])
@constraint(m3,[i = 1:5],x[i] <= 10)

m4 = JuMP.Model()
JuMP.@variable(m4,x <= 1)


#Set models on nodes and edges
Plasmo.setmodel(n1,m1)     #set m1 to node 1.  Updates reference on m1
Plasmo.setmodel(n2,m2)
Plasmo.setmodel(n3,m3)
Plasmo.setmodel(n4,m4)

#Link constraints take the same expressions as the JuMP @constraint macro
Plasmo.@linkconstraint(graph,n4[:x] == n1[:x])

Plasmo.@linkconstraint(graph,[t = 1:5],n4[:x] == n2[:z][t])
Plasmo.@linkconstraint(graph,[i = 1:5],n3[:x][i] == n1[:x])
Plasmo.@linkconstraint(graph,[j = 1:5,i = 1:3],n2[:a][j,i] == n4[:x])

#Get all of the link constraints in a graph
links = Plasmo.getlinkconstraints(graph)
for link in links
    println(link)
end

Plasmo.solve(graph)

println("n1[:x]= ",JuMP.getvalue(n1[:x]))
println("n1[:y]= ",JuMP.getvalue(n1[:y]))

println("n4[:x]= ",JuMP.getvalue(n4[:x]))

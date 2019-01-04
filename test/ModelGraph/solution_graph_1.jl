import JuMP
using Plasmo
import Ipopt

#Create a Graph Model
graph = ModelGraph()
setsolver(graph,Ipopt.IpoptSolver())

#Add nodes to a GraphModel
n1 = add_node!(graph)
n2 = add_node!(graph)
n3 = add_node!(graph)
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
JuMP.@NLconstraint(m2,nlcon,exp(x)+y <= 7)
JuMP.@objective(m2,Min,x)

m3 = JuMP.Model()
JuMP.@variable(m3,x[1:5])

#Set models on nodes and edges
setmodel(n1,m1)     #set m1 to node 1.  Updates reference on m1
setmodel(n2,m2)
setmodel(n3,m3)

#Link constraints take the same expressions as the JuMP @constraint macro
@linkconstraint(graph,n2[:x] == n1[:x])
@linkconstraint(graph,[i = 1:5],n3[:x][i] == n1[:x])

#Solve
solve(graph)

solution = getsolution(graph)

true

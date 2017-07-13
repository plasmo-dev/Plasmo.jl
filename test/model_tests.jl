#DataFlow.jl
#Cassette.jl

import JuMP
import Plasmo
import Ipopt

#Create a Graph Model
graph = Plasmo.GraphModel()
#graph = Plasmo.getgraph(model)

graph.solver = Ipopt.IpoptSolver()

#Add nodes to a GraphModel
n1 = Plasmo.add_node!(graph)
n2 = Plasmo.add_node!(graph)
n3 = Plasmo.add_node!(graph)
#Add edges between the nodes
edge = Plasmo.add_edge!(graph,n1,n2)

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

function simple_model()
  m = JuMP.Model()
  JuMP.@variable(m,x <= 1)
  return m
end

#Add models to nodes and edges by default?
Plasmo.setmodel!(n1,m1)     #set m1 to node 1.  Programatically updates model
Plasmo.setmodel!(n2,m2)
Plasmo.setmodel!(n3,m3)
Plasmo.setmodel!(edge,simple_model())

#check that nodes and edges are connected when linking
Plasmo.@linkconstraint(graph,edge[:x] == n1[:x]) #will work since the node and edge are connected

Plasmo.@linkconstraint(graph,[t = 1:5],edge[:x] == n2[:z][t])
Plasmo.@linkconstraint(graph,[i = 1:5],n3[:x][i] == n1[:x])
Plasmo.@linkconstraint(graph,[j = 1:5,i = 1:3],n2[:a][j,i] == edge[:x])

Plasmo.getlinkconstraints(graph)

Plasmo.solve(graph)

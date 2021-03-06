using Plasmo
using LightGraphs

function create_optigraph()
    optigraph = OptiGraph()
    @optinode(optigraph,nodes[1:4])

    #node 1
    @variable(nodes[1],0 <= x <= 2)
    @variable(nodes[1],0 <= y <= 3)
    @constraint(nodes[1],x+y <= 4)
    @objective(nodes[1],Min,x)

    #node 2
    @variable(nodes[2],x >= 1)
    @variable(nodes[2],0 <= y <= 5)
    @NLconstraint(nodes[2],exp(x)+y <= 7)
    @objective(nodes[2],Min,x)

    #node 3
    @variable(nodes[3],x >= 0)
    @variable(nodes[3],y >= 0)
    @constraint(nodes[3],x + y == 2)
    @objective(nodes[3],Max,x)

    #node 4
    @variable(nodes[4],0 <= x <= 1)
    @variable(nodes[4],y >= 0)
    @constraint(nodes[4],x + y <= 3)
    @objective(nodes[4],Max,y)

    #Link constraints take the same expressions as the JuMP @constraint macro
    @linkconstraint(optigraph,nodes[1][:x] == nodes[2][:x])
    @linkconstraint(optigraph,nodes[2][:y] == nodes[3][:x])
    @linkconstraint(optigraph,nodes[3][:x] == nodes[4][:x])

    return optigraph
end

optigraph = create_optigraph()
n1 = getnode(optigraph,1)
n2 = getnode(optigraph,2)


all_neighbors(optigraph,n1)
all_neighbors(optigraph,n2)

n3 = @optinode(optigraph)
@variable(n3,x >= 0)
@linkconstraint(optigraph,n2[:x] == n3[:x])
all_neighbors(optigraph,n2)


#Set Clique graph


#Set Bipartite graph

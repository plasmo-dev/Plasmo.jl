using Plasmo
using Test

function test_optigraph1
    graph = OptiGraph()
    @optinode(graph,n1)
    @optinode(graph,nodes[1:5])
    @optinode(graph,nodes[1:3,1:3])

    for node in all_nodes(graph)
        @variable(node,x>=0)
        @variable(node,y>=2)
        @constraint(node,x + y == 3)
        @objective(node,Min,y)
    end

    @linkconstraint(graph,n1[:x] == nodes[1][:x])
    @linkconstraint(graph,sum(nodes[i][:x] for i = 1:5) == 5)
    @linkconstraint(graph,nodes[2][:y] == nodes[3][:y],attach = nodes[2])

    @test num_nodes(graph) == 15
    @test num_optiedges(graph) == 3
    @test num_linkconstraints(graph) == 3
end

function test_optigraph2
    graph = OptiGraph()

    #Add nodes to a GraphModel
    @optinode(graph,n1)
    @optinode(graph,n2)
    @optinode(graph,n3)
    @optinode(graph,n4)

    @variable(n1,0 <= x <= 2)
    @variable(n1,0 <= y <= 3)
    @NLconstraint(n1,x^3+y <= 4)
    # @objective(n1,Min,x)


    vals = collect(1:5)
    grid = 1:3
    @variable(n2,x >= 1)
    @variable(n2,0 <= y <= 5)
    @variable(n2,z[1:5] >= 0)
    @variable(n2,a[vals,grid] >=0 )
    @NLconstraint(n2,exp(x)+y <= 7)
    # @objective(n2,Min,x)

    @variable(n3,x[1:5])
    @variable(n4,x <= 1)


    #Link constraints take the same expressions as the JuMP @constraint macro
    @linkconstraint(graph,n4[:x] == n1[:x])
    @linkconstraint(graph,[t = 1:5],n4[:x] == n2[:z][t])
    @linkconstraint(graph,[i = 1:5],n3[:x][i] == n1[:x])
    @linkconstraint(graph,[j = 1:5,i = 1:3],n2[:a][j,i] == n4[:x])
    @linkconstraint(graph,[i = 1:3],n1[:x] + n2[:z][i] + n3[:x][i] + n4[:x] >= 0)

    @objective(graph,Min,n1[:x] + n2[:x])
end

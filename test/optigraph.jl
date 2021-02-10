using Plasmo
using JuMP
using Test

module TestOptiGraph

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
    @test num_variables(graph) == 30
end

function test_optigraph2
    graph = OptiGraph()

    @optinode(graph,n1)
    @optinode(graph,n2)
    @optinode(graph,n3)
    @optinode(graph,n4)

    @variable(n1,0 <= x <= 2)
    @variable(n1,0 <= y <= 3)
    @NLconstraint(n1,x^3+y <= 4)

    vals = collect(1:5)
    grid = 1:3
    @variable(n2,x >= 1)
    @variable(n2,0 <= y <= 5)
    @variable(n2,z[1:5] >= 0)
    @variable(n2,a[vals,grid] >=0 )
    @NLconstraint(n2,exp(x)+y <= 7)

    @variable(n3,x[1:5])
    @variable(n4,x <= 1)


    @linkconstraint(graph,n4[:x] == n1[:x])
    @linkconstraint(graph,[t = 1:5],n4[:x] == n2[:z][t])
    @linkconstraint(graph,[i = 1:5],n3[:x][i] == n1[:x])
    @linkconstraint(graph,[j = 1:5,i = 1:3],n2[:a][j,i] == n4[:x])
    @linkconstraint(graph,[i = 1:3],n1[:x] + n2[:z][i] + n3[:x][i] + n4[:x] >= 0)

    @objective(graph,Min,n1[:x] + n2[:x])

    @test has_nlp_data(graph) == true
end


function test_set_model()
    graph = OptiGraph()
    optimizer = Ipopt.Optimizer

    n1 = @node(graph)
    n2 = @node(graph)

    m1 = JuMP.Model()
    JuMP.@variable(m1,0 <= x <= 2)
    JuMP.@variable(m1,0 <= y <= 3)
    JuMP.@constraint(m1,x+y <= 4)
    JuMP.@objective(m1,Min,x)

    m2 = JuMP.Model()
    JuMP.@variable(m2,x)
    JuMP.@NLconstraint(m2,ref,exp(x) >= 2)

    #Set models on nodes and edges
    set_model(n1,m1)     #set m1 to node 1.  Updates reference on m1
    set_model(n2,m2)

    #Link constraints take the same expressions as the JuMP @constraint macro
    @linkconstraint(graph,n1[:x] == n2[:x])

    optimize!(graph,optimizer)

    println("n1[:x]= ",value(n1,n1[:x]))
    println("n2[:x]= ",value(n2,n2[:x]))
    println("objective = ", objective_value(graph))
end

function test_subgraph()
    graph = OptiGraph()

    @optinode(graph,n0)
    @variable(n0,x)

    sg1 = OptiGraph()
    sg2 = OptiGraph()
    add_subgraph!(graph,sg1)
    add_subgraph!(graph,sg2)

    @optinode(sg1,ng1[1:5])
    @optinode(sg2,ng2[1:5])

    for node in getnodes(sg1)
        @variable(node,0 <= x <= 2)
        @objective(node,Max,x)
    end

    for node in getnodes(sg2)
        @variable(node,x>=2)
        @objective(node,Min,x)
    end

    @linkconstraint(sg1,sum(ng1[i][:x] for i = 1:5) <= 4)
    @linkconstraint(sg2,sum(ng2[i][:x] for i = 1:5) >= 4)

    @linkconstraint(graph,n0[:x] == ng1[1][:x])
    @linkconstraint(graph,n0[:x] == ng2[1][:x])

    @test num_nodes(graph) == 1
    @test length(all_nodes(graph)) == 11
    @test num_optiedges(graph) == 2
    @test num_all_optiedges(graph) == 4
end

function runtests()
    for name in names(@__MODULE__; all = true)
        if !startswith("$(name)", "test_")
            continue
        end
        @testset "$(name)" begin
            getfield(@__MODULE__, name)()
        end
    end
end

end

TestOptiGraph.run_tests()

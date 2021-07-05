module TestOptiGraph

using Plasmo
using JuMP
using Ipopt
using Test

function _create_optigraph()
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
    return graph
end

function test_optigraph1()
    graph = OptiGraph()
    @optinode(graph,n1)
    @optinode(graph,nodes1[1:5])
    @optinode(graph,nodes2[1:3,1:3])

    for node in all_nodes(graph)
        @variable(node,x>=0)
        @variable(node,y>=2)
        @constraint(node,x + y == 3)
        @objective(node,Min,y)
    end

    @linkconstraint(graph,n1[:x] == nodes1[1][:x])
    @linkconstraint(graph,sum(nodes1[i][:x] for i = 1:5) == 5)
    @linkconstraint(graph,nodes2[2][:y] == nodes2[3][:y],attach = nodes2[2])

    @test num_nodes(graph) == 15
    @test num_optiedges(graph) == 3
    @test num_link_constraints(graph) == 3
    @test num_variables(graph) == 30
end

function test_optigraph2()
    graph = _create_optigraph()
    @test Plasmo.has_nlp_data(graph) == true
    @test Plasmo.has_objective(graph) == true
    @test Plasmo.has_nl_objective(graph) == false
    @test Plasmo.has_node_objective(graph) == true
end

function test_set_model()
    graph = OptiGraph()

    n1 = @optinode(graph)
    n2 = @optinode(graph)

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

    @test num_variables(graph) == 3
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
    @test num_all_nodes(graph) == 11
    @test num_optiedges(graph) == 2
    @test num_all_optiedges(graph) == 4
    @test num_subgraphs(graph) == 2
end

function test_multiple_solves()
    graph = _create_optigraph()
    n1 = getnode(graph,1)
    set_optimizer(graph,Ipopt.Optimizer)
    optimize!(graph)
    @test isapprox(value(n1[:x]),0,atol = 1e-6)

    set_lower_bound(n1[:x],1)
    optimize!(graph)
    isapprox(value(n1[:x]),1,atol = 1e-6)
end

function test_fix_variable()
    graph = _create_optigraph()
    n1 = getnode(graph,1)
    fix(n1[:x],1,force = true)
    set_optimizer(graph,Ipopt.Optimizer)
    optimize!(graph)
    @test value(n1[:x]) == 1

    fix(n1[:x],2)
    optimize!(graph)
    @test value(n1[:x]) == 2

    fix(n1[:x],0)
    optimize!(graph)
    @test value(n1[:x]) == 0
end

function test_set_optimizer_attributes()
    graph = _create_optigraph()
    set_optimizer(graph,Ipopt.Optimizer)
    JuMP.set_optimizer_attribute(graph,"max_cpu_time",1e2)
    @test JuMP.get_optimizer_attribute(graph,"max_cpu_time") == 100.0
end

# Test optigraph optimizer.  This is a way to set custom optimize calls on an optimizer
# to make it work with an optigraph.
mutable struct TestOptimizer <: MOI.AbstractOptimizer
    status::MOI.TerminationStatusCode
end
TestOptimizer() = TestOptimizer(MOI.OPTIMIZE_NOT_CALLED)
MOI.get(optimizer::TestOptimizer,::MOI.TerminationStatus) = optimizer.status
MOI.get(optimizer::TestOptimizer,::Plasmo.OptiGraphOptimizeHook) = optigraph_optimize!

MOI.is_empty(::TestOptimizer) = true
MOI.empty!(::TestOptimizer) = nothing
MOI.copy_to(dest::TestOptimizer,src::MOI.ModelLike;kwargs...) = MOIU.default_copy_to(dest,src;kwargs...)
MOIU.supports_default_copy_to(model::TestOptimizer, copy_names::Bool) = true

function optigraph_optimize!(graph::OptiGraph,optimizer::TestOptimizer)
    println("Running Test Optimizer")
    for node in all_nodes(graph)
        vars = all_variables(node)
        vals = ones(length(vars))
        Plasmo.set_node_primals(node,vars,vals)
        Plasmo.set_node_status(node,MOI.OPTIMAL)
    end
    optimizer.status = MOI.OPTIMAL
    return nothing
end

function test_optigraph_optimizer()
    graph = _create_optigraph()
    test_optimizer = TestOptimizer
    set_optimizer(graph,test_optimizer)
    Plasmo.optimize!(graph)
    for var in all_variables(graph)
        @test value(var) == 1.0
    end
end

function run_tests()
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

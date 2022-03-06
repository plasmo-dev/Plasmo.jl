module TestOptiNode

using Plasmo
using JuMP
using Ipopt
using Test

function test_optinode1()
    node = OptiNode()

    #object dictionary
    @test node.model.ext[:optinode] == node

    #jump_model
    @test jump_model(node) == node.model

    #getindex, setindex
    node[:p] = 2
    @test node[:p] == 2

    #label
    set_label(node,"test")
    @test Plasmo.label(node) == "test"

    #variables
    @variable(node,x)
    @test JuMP.object_dictionary(node)[:x] == x
    @test JuMP.all_variables(node) == JuMP.VariableRef[x]
    @test is_node_variable(x) == true
    @test is_node_variable(node,x) == true
    @test getnode(x) == node

    m = JuMP.Model()
    @variable(m,x >= 0)
    @test is_set_to_node(m) == false
    set_model(node,m)
    @test is_set_to_node(m) == true
    @test num_variables(node) == 1
    @test isa(JuMP.backend(m),Plasmo.NodeBackend)
    @test getnode(m) == node


    @variable(node,y >= 0)
    @constraint(node,cref, x + y >= 3)
    @test num_constraints(node) == 1
    @test num_nl_constraints(node) == 0
    @test getnode(cref) == node

    @NLconstraint(node, x^3 >= 8)
    @test num_nl_constraints(node) == 1

    @test has_objective(node) == false
    @objective(node,Min,x)
    @test has_objective(node) == true

    @test has_nl_objective(node) == false
    @NLobjective(node,Min,x^3)
    @test has_nl_objective(node) == true

    set_optimizer(node,optimizer_with_attributes(Ipopt.Optimizer,"print_level" => 0))
    optimize!(node)

    @test isapprox(objective_value(node),8)
    @test isapprox(round(dual(cref)),0)
    @test isapprox(value(x),2)
    @test isapprox(value(node,x),2)
end

function test_optinode2()
    graph = OptiGraph()
    n1 = add_node!(graph)
    n2 = add_node!(graph)

    @test num_linked_variables(n1) == 0
    @variable(n1,x)
    @variable(n2,x)
    @linkconstraint(graph,n1[:x] == n2[:x])
    @test num_linked_variables(n1) == 1
    @test num_linked_variables(n2) == 1
end

function test_optinode3()
    graph = OptiGraph()
    n1 = add_node!(graph)

    @variable(n1,x>=0)
    @NLparameter(n1,p == 1)
    @test n1.nlp_data.nlparamvalues[1] == 1
    @test n1.nlp_data == n1.model.nlp_data
    @NLconstraint(n1,x^3 + p == 2)

    graph = OptiGraph()
    n1 = add_node!(graph)
    @variable(n1,x>=0)
    @variable(n1,y>=0)
    @NLexpression(n1,exp,x^3 + 5)
    @test length(n1.nlp_data.nlexpr) == 1
    @test n1.nlp_data == n1.model.nlp_data
    @NLconstraint(n1,exp +y <= 5)
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

TestOptiNode.run_tests()

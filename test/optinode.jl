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
    set_label(node, "test")
    @test Plasmo.label(node) == "test"

    #variables
    @variable(node, x)
    @test JuMP.object_dictionary(node)[:x] == x
    @test JuMP.all_variables(node) == JuMP.VariableRef[x]
    @test is_node_variable(x) == true
    @test is_node_variable(node, x) == true
    @test optinode(x) == node

    m = JuMP.Model()
    @variable(m, x >= 0)
    @test is_set_to_node(m) == false
    set_model(node, m)
    @test is_set_to_node(m) == true
    @test num_variables(node) == 1
    @test isa(JuMP.backend(m), Plasmo.NodeBackend)
    @test optinode(m) == node
    @test optinode(x) == node

    @variable(node, y >= 0)
    @constraint(node, cref, x + y >= 3)
    @test num_constraints(node) == 1
    @test num_nonlinear_constraints(node) == 0
    @test optinode(cref) == node

    @NLconstraint(node, nl_cref, x^3 >= 8)
    @test num_nonlinear_constraints(node) == 1

    @test has_objective(node) == false
    @objective(node, Min, x)
    @test has_objective(node) == true

    @test has_nl_objective(node) == false
    @NLobjective(node, Min, x^3)
    @test has_nl_objective(node) == true

    set_optimizer(node, optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0))
    optimize!(node)

    @test isapprox(objective_value(node), 8)
    @test isapprox(round(dual(cref)), 0)
    @test isapprox(value(x), 2)
    @test isapprox(value(node, x), 2)

    @test JuMP.termination_status(node) == MOI.LOCALLY_SOLVED
    @test JuMP.raw_status(node) == "Solve_Succeeded"
    @test JuMP.primal_status(node) == MOI.FEASIBLE_POINT
    @test JuMP.dual_status(node) == MOI.FEASIBLE_POINT
    @test JuMP.solver_name(node) == "Ipopt"
    @test JuMP.mode(node) == MOIU.AUTOMATIC
    @test Base.string(node) == "OptiNode w/ 2 Variable(s) and 2 Constraint(s)"

    # @test nodevalue(x) == value(x)
    # @test nodevalue(x + y) == value(x + y)
    # @test nodevalue(x + y^2) == value(x + y^2)
end

function test_optinode2()
    graph = OptiGraph()
    n1 = add_node!(graph)
    n2 = add_node!(graph)

    @test num_linked_variables(n1) == 0
    @variable(n1, x)
    @variable(n2, x)
    @linkconstraint(graph, n1[:x] == n2[:x])
    @test num_linked_variables(n1) == 1
    @test num_linked_variables(n2) == 1
    @test num_linkconstraints(n1) == 1
end

function test_optinode3()
    graph = OptiGraph()
    n1 = add_node!(graph)

    @variable(n1, x >= 0)
    @NLparameter(n1, p == 1)
    @test nonlinear_model(n1).parameters[1] == 1

    @NLconstraint(n1, x^3 + p == 2)
    c_idx = MOI.Nonlinear.ConstraintIndex(1)
    @test JuMP.nonlinear_constraint_string(n1, MIME("text/latex"), c_idx) ==
        "(n1[:x] ^ {3.0} + p) - 2.0 = 0"

    graph = OptiGraph()
    n1 = add_node!(graph)
    @variable(n1, x >= 0)
    @variable(n1, y >= 0)
    @expression(n1, ref1, x + y)
    @expression(n1, ref2, x^2 + y^2)
    @NLexpression(n1, exp, x^3 + 5)

    @NLconstraint(n1, exp + y <= 5)

    #NL exceptions
    @test_throws Exception @NLconstraint(n1, n1 >= 0)
end

function test_optinode_set_solution()
    graph = OptiGraph()
    n1 = add_node!(graph)
    n2 = add_node!(graph)

    @variable(n1, x >= 0)
    @variable(n1, y >= 0)
    @constraint(n1, conref, x + y == 2)

    @variable(n2, x >= 0)
    @linkconstraint(graph, n1[:x] == n2[:x])

    set_node_primals(n1, [n1[:x], n1[:y]], [0.0, 1.0])
    set_node_duals(n1, [conref], [0.0])
    set_node_status(n1, MOI.OPTIMAL)

    @test value(n1[:x]) == 0
    @test value(n1[:y]) == 1
    @test dual(conref) == 0
    @test JuMP.termination_status(n1) == MOI.OPTIMAL
end

function test_optinode_set_optimizer_attributes()
    graph = OptiGraph()
    n1 = add_node!(graph)
    set_optimizer(n1, optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0))
    JuMP.set_optimizer_attribute(n1, "max_cpu_time", 1e2)
    @test JuMP.get_optimizer_attribute(n1, "max_cpu_time") == 100.0
end

function run_tests()
    for name in names(@__MODULE__; all=true)
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

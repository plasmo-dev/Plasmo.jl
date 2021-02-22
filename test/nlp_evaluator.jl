module TestNLPEvaluator

using Plasmo
using JuMP
using Ipopt
using Test

#########################################################
#Plasmo model to check evaluator functions
#########################################################
function _make_plasmo_graph()
    graph = OptiGraph()
    @optinode(graph,n1)
    @variable(n1,x[1:5] >= 0)
    @variable(n1,y[1:5] >= 0)
    @constraint(n1,ref1,sum(x) <= 10)
    @constraint(n1,ref2,sum(y) <= 5)
    @NLobjective(n1,Min,sum(n1[:x][i] for i = 1:5)^3)
    @NLconstraint(n1,nlref,x[1]^2 + x[2]^2 <= 5)


    @optinode(graph,n2)
    @variable(n2,x[1:5] >= 0)
    @variable(n2,y[1:5] >= 0)
    @constraint(n2,ref1,sum(x) <= 10)
    @constraint(n2,ref2,sum(y) <= 5)
    @NLconstraint(n2,x[1]^2 + x[2]^2 <= 5)
    @objective(n2,Min,sum(n2[:x][i]^2 for i = 1:5))

    @linkconstraint(graph,[i = 1:5],n1[:y][i] == n2[:y][i])

    return graph
end

#########################################################
#JuMP version to check Evaluator functions
#########################################################
function _make_jump_model()
    model = Model()

    #"Node 1"
    @variable(model,x1[1:5] >= 0)
    @variable(model,y1[1:5] >= 0)
    @constraint(model,ref11,sum(x1) <= 10)
    @constraint(model,ref12,sum(y1) <= 5)
    @NLconstraint(model,x1[1]^2 + x1[2]^2 <= 5)

    #"Node 2"
    @variable(model,x2[1:5] >= 0)
    @variable(model,y2[1:5] >= 0)
    @constraint(model,ref1,sum(x2) <= 10)
    @constraint(model,ref2,sum(y2) <= 5)
    @NLconstraint(model,x2[1]^2 + x2[2]^2 <= 5)

    #"Link Constraint"
    @constraint(model,[i = 1:5],y1[i] == y2[i])

    #This sets local objective functions on the corresponding "nodes"
    @NLobjective(model,Min,sum(x1[i] for i = 1:5)^3 + sum(x2[i]^2 for i = 1:5))

    return model
end


function test_plasmo_nlp_evaluator()
    graph = _make_plasmo_graph()

    x1 = ones(20)
    g1 = zeros(20)
    c1 = zeros(2)
    mu1 = ones(2)

    d1 = Plasmo.OptiGraphNLPEvaluator(graph)
    MOI.initialize(d1,[:Hess,:Jac,:Grad])
    obj1 = MOI.eval_objective(d1,x1)
    @test obj1 == 130.0

    MOI.eval_objective_gradient(d1,g1,x1)
    @test g1 == [ones(5)*75;zeros(5);ones(5)*2;zeros(5)]

    hess_structure1 = MOI.hessian_lagrangian_structure(d1)
    @test length(hess_structure1) == 24

    jac_structure1 = MOI.jacobian_structure(d1)
    @test length(jac_structure1) == 4

    MOI.eval_constraint(d1,c1,x1)
    @test c1 == [-3,-3]

    hess_inds1 = sortperm(hess_structure1)
    hess_vals1 = zeros(length(hess_structure1))
    MOI.eval_hessian_lagrangian(d1,hess_vals1,x1,1.0,mu1)
    @test hess_vals1 == [ones(15)*30;ones(9)*2]

    jac_vals1 = zeros(length(jac_structure1))
    MOI.eval_constraint_jacobian(d1,jac_vals1,x1)
    @test jac_vals1 == ones(4)*2
end

function test_evaluator_matches_jump_result()
    graph = _make_plasmo_graph()
    x1 = ones(20)
    g1 = zeros(20)
    c1 = zeros(2)
    mu1 = ones(2)

    d1 = Plasmo.OptiGraphNLPEvaluator(graph)
    MOI.initialize(d1,[:Hess,:Jac,:Grad])
    obj1 = MOI.eval_objective(d1,x1)
    MOI.eval_objective_gradient(d1,g1,x1)
    hess_structure1 = MOI.hessian_lagrangian_structure(d1)
    jac_structure1 = MOI.jacobian_structure(d1)
    MOI.eval_constraint(d1,c1,x1)
    hess_inds1 = sortperm(hess_structure1)
    hess_vals1 = zeros(length(hess_structure1))
    MOI.eval_hessian_lagrangian(d1,hess_vals1,x1,1.0,mu1)
    jac_vals1 = zeros(length(jac_structure1))
    MOI.eval_constraint_jacobian(d1,jac_vals1,x1)

    model = _make_jump_model()
    x2 = ones(20)
    g2 = zeros(20)
    c2 = zeros(2)
    mu2 = ones(2)

    d2 = JuMP.NLPEvaluator(model)
    MOI.initialize(d2,[:Hess,:Jac])
    obj2 = MOI.eval_objective(d2,x2)
    MOI.eval_objective_gradient(d2,g2,x2)
    hess_structure2 = MOI.hessian_lagrangian_structure(d2)
    jac_structure2 = MOI.jacobian_structure(d2)
    MOI.eval_constraint(d2,c2,x2)

    hess_inds2 = sortperm(hess_structure2)
    hess_vals2 = zeros(length(hess_structure2))
    MOI.eval_hessian_lagrangian(d2,hess_vals2,x2,1.0,mu2)

    jac_vals2 = zeros(length(jac_structure2))
    MOI.eval_constraint_jacobian(d2,jac_vals2,x2)

    #checks
    @test obj1 == obj2
    @test g1 == g2
    @test c1 == c2
    @test hess_vals1[hess_inds1] == hess_vals2[hess_inds2]
    @test jac_vals1 == jac_vals2

    set_optimizer(graph,Ipopt.Optimizer)
    optimize!(graph)

    set_optimizer(model,Ipopt.Optimizer)
    optimize!(model)

    val_graph = value.(all_variables(graph))
    val_model = value.(all_variables(model))
    @test val_graph == val_model
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

TestNLPEvaluator.run_tests()

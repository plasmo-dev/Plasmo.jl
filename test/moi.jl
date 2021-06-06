module TestMOI

using Plasmo
using Ipopt
using Test

function test_node_backend_1()
    node = OptiNode()
    @variable(node,x,start = 1)
    node_backend = backend(node)

    @test node.id == node_backend.node_id
    @test node_backend.node_id == node_backend.last_solution_id
    @test MOI.get(node_backend,MOI.NumberOfVariables()) == 1

    @variable(node,y,start = 2)
    @test MOI.get(node_backend,MOI.NumberOfVariables()) == 2

    @constraint(node,c1,x + y == 2)
    @test MOI.get(node_backend,MOI.NumberOfConstraints{MOI.ScalarAffineFunction{Float64},MOI.EqualTo{Float64}}()) == 1

    @test MOI.get(node_backend,MOI.VariablePrimalStart(),index(x)) == 1

    MOI.set(node_backend,MOI.VariablePrimalStart(),index(x),2)
    @test MOI.get(node_backend,MOI.VariablePrimalStart(),index(x)) == 2

    @test MOI.is_valid(node_backend,index(x))

    @test MOI.supports_constraint(node_backend,MOI.ScalarAffineFunction{Float64},MOI.EqualTo{Float64})

    @test MOIU.state(node_backend) == MOIU.NO_OPTIMIZER
    optimizer = Ipopt.Optimizer
    set_optimizer(node,optimizer)
    @test MOIU.state(node_backend) == MOIU.EMPTY_OPTIMIZER

    MOIU.attach_optimizer(node_backend)
    @test MOIU.state(node_backend) == MOIU.ATTACHED_OPTIMIZER

    MOIU.drop_optimizer(node_backend)
    @test MOIU.state(node_backend) == MOIU.NO_OPTIMIZER

    set_optimizer(node,optimizer)
    MOIU.attach_optimizer(node_backend)
    MOIU.reset_optimizer(node_backend,Ipopt.Optimizer())
    @test MOIU.state(node_backend) == MOIU.EMPTY_OPTIMIZER

end

function test_set_solution()
    node = OptiNode()
    @variable(node,x,start = 1)
    @variable(node,y,start = 2)
    @constraint(node,c1,x + y == 2)

    node_backend = backend(node)
    vars = MOI.get(node_backend,MOI.ListOfVariableIndices())
    values = [1.0,1.0]

    @test Plasmo.has_node_solution(node_backend,node_backend.node_id) == false

    Plasmo.set_node_primals!(node_backend,vars,values,node.id)
    @test MOI.get(node_backend,MOI.VariablePrimal(),vars) == [1.0,1.0]

    cons = Vector{MOI.ConstraintIndex}(undef,0)
    # cons = MOI.ConstraintIndex{F,S}[]
    cidx_duals = Float64[]
    con_list = MOI.get(node_backend,MOI.ListOfConstraints())
    for (F,S) in con_list
        cidx = MOI.get(node_backend,MOI.ListOfConstraintIndices{F,S}())
        append!(cons,cidx)
        append!(cidx_duals,ones(length(cidx)))
    end
    Plasmo.set_node_duals!(node_backend,cons,cidx_duals,node.id)
    @test MOI.get(node_backend,MOI.ConstraintDual(),cons) == [1.0]
end

#function test_append_backend
#end

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

TestMOI.run_tests()

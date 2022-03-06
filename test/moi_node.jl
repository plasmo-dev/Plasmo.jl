module TestMOINode

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
    set_optimizer(node,optimizer_with_attributes(Ipopt.Optimizer,"print_level" => 0))
    @test MOIU.state(node_backend) == MOIU.EMPTY_OPTIMIZER

    MOIU.attach_optimizer(node_backend)
    @test MOIU.state(node_backend) == MOIU.ATTACHED_OPTIMIZER

    MOIU.drop_optimizer(node_backend)
    @test MOIU.state(node_backend) == MOIU.NO_OPTIMIZER

    set_optimizer(node,optimizer_with_attributes(Ipopt.Optimizer,"print_level" => 0))
    MOIU.attach_optimizer(node_backend)
    MOIU.reset_optimizer(node_backend)#,Ipopt.Optimizer())
    @test MOIU.state(node_backend) == MOIU.EMPTY_OPTIMIZER
end

#TODO: more tests
# function test_node_backend_2()
# end

function test_set_solution()
    node = OptiNode()
    @variable(node,x,start = 1)
    @variable(node,y,start = 2)
    @constraint(node,c1,x + y == 2)

    #set primals
    node_backend = backend(node)
    vars = MOI.get(node_backend,MOI.ListOfVariableIndices())
    values = [1.0,1.0]
    @test Plasmo.has_node_solution(node_backend,node_backend.node_id) == false
    Plasmo.set_backend_primals!(node_backend,vars,values,node.id)
    @test MOI.get(node_backend,MOI.VariablePrimal(),vars) == [1.0,1.0]
    @test Plasmo.has_node_solution(node_backend,node_backend.node_id) == true

    #set duals
    cons = Vector{MOI.ConstraintIndex}(undef,0)
    cidx_duals = Float64[]
    con_list = MOI.get(node_backend,MOI.ListOfConstraintTypesPresent())
    for (F,S) in con_list
        cidx = MOI.get(node_backend,MOI.ListOfConstraintIndices{F,S}())
        append!(cons,cidx)
        append!(cidx_duals,ones(length(cidx)))
    end
    Plasmo.set_backend_duals!(node_backend,cons,cidx_duals,node.id)
    @test MOI.get(node_backend,MOI.ConstraintDual(),cons) == [1.0]

    #set duals before setting primals
    node = OptiNode()
    @variable(node,x,start = 1)
    @variable(node,y,start = 2)
    @constraint(node,c1,x + y == 2)

    node_backend = backend(node)
    cons = Vector{MOI.ConstraintIndex}(undef,0)
    cidx_duals = Float64[]
    con_list = MOI.get(node_backend,MOI.ListOfConstraintTypesPresent())
    for (F,S) in con_list
        cidx = MOI.get(node_backend,MOI.ListOfConstraintIndices{F,S}())
        append!(cons,cidx)
        append!(cidx_duals,ones(length(cidx)))
    end
    Plasmo.set_backend_duals!(node_backend,cons,cidx_duals,node.id)
    @test MOI.get(node_backend,MOI.ConstraintDual(),cons) == [1.0]

    #set status
    Plasmo.set_backend_status!(node_backend,MOI.OTHER_LIMIT,node.id)
    @test MOI.get(node_backend,MOI.TerminationStatus()) == MOI.OTHER_LIMIT

    node = OptiNode()
    @variable(node,x,start = 1)
    @variable(node,y,start = 2)
    @constraint(node,c1,x + y == 2)

    node_backend = backend(node)
    Plasmo.set_backend_status!(node_backend,MOI.OTHER_LIMIT,node.id)
    @test MOI.get(node_backend,MOI.TerminationStatus()) == MOI.OTHER_LIMIT
    Plasmo.set_backend_primals!(node_backend,vars,values,node.id)
    @test MOI.get(node_backend,MOI.VariablePrimal(),vars) == [1.0,1.0]
end

function test_multiple_graph_changes()
    graph = OptiGraph()
    @optinode(graph,nodes[1:4])
    for node in nodes
        @variable(node,x>=0)
    end
    @objective(graph,Min,sum(node[:x] for node in nodes))
    @linkconstraint(graph,[i=1:3],nodes[i][:x] == nodes[i+1][:x])
    set_optimizer(graph,optimizer_with_attributes(Ipopt.Optimizer,"print_level" => 0))
    optimize!(graph)

    sub = Plasmo.induced_subgraph(graph,nodes[1:2])
    set_optimizer(sub,optimizer_with_attributes(Ipopt.Optimizer,"print_level" => 0))
    optimize!(sub)

    #add variable and constraint to node pointer
    @variable(nodes[1],y >= 0)
    @constraint(nodes[1],y + nodes[1][:x] == 2)
    optimize!(sub)
end

#TODO
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

TestMOINode.run_tests()

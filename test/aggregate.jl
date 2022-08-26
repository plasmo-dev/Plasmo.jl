module TestAggregatation

using Plasmo
using Test

function _create_test_optigraph()
    graph = OptiGraph()
    @optinode(graph, nodes[1:100])
    for node in nodes
        @variable(node, 0 <= x <= 2)
        @variable(node, 0 <= y <= 3)
        @NLconstraint(node, x^3+y <= 4)
    end
    @linkconstraint(graph,links[i=1:99],nodes[i][:x] == nodes[i+1][:x])
    @objective(graph,Min,sum(node[:y] for node in nodes))
    return graph
end

function _create_test_optigraph_w_subgraphs()
    graph = _create_test_optigraph()
    node_vectors = [graph.optinodes[1:20], graph.optinodes[21:40],
    graph.optinodes[41:60], graph.optinodes[61:80], graph.optinodes[81:100]]
    partition = Partition(graph, node_vectors)
    apply_partition!(graph, partition)
    return graph
end

function _create_test_optigraph_w_recursive_subgraphs()
    graph = _create_test_optigraph_w_subgraphs()
    for sg in subgraphs(graph)
        node_vectors = [sg.optinodes[1:10],sg.optinodes[11:20]]
        partition = Partition(sg,node_vectors)
        apply_partition!(sg,partition)
    end
    return graph
end

function test_affine_quadratic_aggregate()
    graph = OptiGraph()

    n1 = @optinode(graph)
    n2 = @optinode(graph)

    @variable(n1,0 <= x <= 2)
    @variable(n1,0 <= y <= 3)
    @variable(n1, z >= 0)
    @constraint(n1,x+y+z >= 4)

    @variable(n2,x)
    @variable(n2,z >= 0)
    @constraint(n2,z + x >= 4)
    @constraint(n2,z^2 + x^2 <= 12)

    @linkconstraint(graph,n1[:x] == n2[:x])
    @linkconstraint(graph,n1[:z] == n2[:z])

    @objective(graph,Min,n1[:y] + n2[:x] + n1[:z])

    aggregate_node,reference_map = aggregate(graph)

    @test num_variables(graph) == 5
    @test num_variables(graph) == num_variables(aggregate_node)
end

function test_nonlinear_aggregate()
    graph = OptiGraph()
    @optinode(graph, n1)
    @variable(n1, x[1:2] <= 2)
    set_start_value(x[1], 2)
    set_start_value(x[2], 1)
    @NLobjective(n1, Max, x[1]^2 + x[2]^2)

    @optinode(graph,n2)
    @variable(n2,x[1:2] >= 0)
    set_start_value(x[1],2)
    set_start_value(x[2],2)
    @NLobjective(n2,Min,x[1]^3 + x[2]^2)

    new_node,ref = aggregate(graph)

    @test num_variables(graph) == 4
    @test num_variables(graph) == num_variables(new_node)

    #test start values
    all_vars = all_variables(new_node)
    @test all(start_value.(all_vars) .== [2,1,2,2])
end

function test_aggregate_to_subgraphs()
    graph = _create_test_optigraph_w_subgraphs()
    new_graph,ref = aggregate(graph,0)
    @test num_all_nodes(new_graph) == 5
    @test num_all_linkconstraints(new_graph) == 4

    aggregate!(graph,0)
    @test num_all_nodes(graph) == 5
    @test num_all_linkconstraints(graph) == 4

    #TODO: more checks
    graph = _create_test_optigraph_w_recursive_subgraphs()
    new_graph,ref = aggregate(graph,1)
    @test num_all_subgraphs(new_graph) == 5
end

function test_objective_copy()
    graph = OptiGraph()
    n1 = @optinode(graph)
    n2 = @optinode(graph)
    @variable(n1, 0 <= x <= 2)
    @variable(n2, 0 <= x <= 3)
    @objective(n1, Min, n1[:x])
    @objective(n2, Min, n2[:x])
    agg_node,ref = aggregate(graph)
    @test objective_function(agg_node) == ref[n1[:x]] + ref[n2[:x]]

    graph = OptiGraph()

    #Nonlinear
    n1 = @optinode(graph)
    @variable(n1,0 <= x <= 2)
    @variable(n1,0 <= y <= 2)
    @NLobjective(n1,Max,x^3 + y^2)

    #VariableRef
    n2 = @optinode(graph)
    @variable(n2,x >= 0)
    @objective(n2,Min,x)

    #Affine
    n3 = @optinode(graph)
    @variable(n3,x >= 0)
    @objective(n3,Min,2*x)

    #Quadratic
    n4 = @optinode(graph)
    @variable(n4,x >= 0)
    @objective(n4,Min,x^2)

    agg_node,ref = aggregate(graph)
    @test has_nl_objective(agg_node) == true
end

function test_copy_node()
    graph = OptiGraph()
    @optinode(graph,n1)
    @variable(n1,x[1:2] <= 2)
    set_start_value(x[1],2)
    set_start_value(x[2],1)
    @NLobjective(n1,Max,x[1]^2 + x[2]^2)

    copied_node,ref = Plasmo._copy_node(n1)
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


end #module

TestAggregatation.run_tests()

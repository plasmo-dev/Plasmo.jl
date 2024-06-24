module TestAggregatation

using Plasmo
using HiGHS
using Test

function _create_test_optigraph()
    graph = OptiGraph()
    @optinode(graph, nodes[1:10])
    for node in nodes
        @variable(node, 0 <= x <= 2)
        @variable(node, 0 <= y <= 3)
        @constraint(node, x + y >= 0)
        @constraint(node, x^2 + y^2 <= 10)
        @constraint(node, x^3 + y <= 4)
    end
    @linkconstraint(graph, links[i=1:9], nodes[i][:x] == nodes[i + 1][:x])
    @objective(graph, Min, sum(node[:y] for node in nodes))
    return graph
end

function test_aggregate_solution()
    graph = _create_test_optigraph()
    agg_node, ref_map = aggregate(graph)

    set_optimizer(graph, HiGHS.Optimizer)
    optimize!(graph)

    set_optimizer(agg_node, HiGHS.Optimizer)
    optimize!(agg_node)

end


# function test_nonlinear_aggregate()
#     graph = OptiGraph()
#     @optinode(graph, n1)
#     @variable(n1, x[1:2] <= 2)
#     set_start_value(x[1], 2)
#     set_start_value(x[2], 1)
#     @NLobjective(n1, Max, x[1]^2 + x[2]^2)

#     @optinode(graph, n2)
#     @variable(n2, x[1:2] >= 0)
#     set_start_value(x[1], 2)
#     set_start_value(x[2], 2)
#     @NLobjective(n2, Min, x[1]^3 + x[2]^2)

#     new_node, ref = aggregate(graph)

#     @test num_variables(graph) == 4
#     @test num_variables(graph) == num_variables(new_node)

#     #test start values
#     all_vars = all_variables(new_node)
#     @test all(start_value.(all_vars) .== [2, 1, 2, 2])
# end

# function test_aggregate_to_subgraphs()
#     graph = _create_test_optigraph_w_subgraphs()
#     new_graph, ref = aggregate(graph, 0)
#     @test num_all_nodes(new_graph) == 5
#     @test num_all_linkconstraints(new_graph) == 4

#     aggregate!(graph, 0)
#     @test num_all_nodes(graph) == 5
#     @test num_all_linkconstraints(graph) == 4

#     #TODO: more checks
#     graph = _create_test_optigraph_w_recursive_subgraphs()
#     new_graph, ref = aggregate(graph, 1)
#     @test num_all_subgraphs(new_graph) == 5
# end

# function test_copy_node()
#     graph = OptiGraph()
#     @optinode(graph, n1)
#     @variable(n1, x[1:2] <= 2)
#     set_start_value(x[1], 2)
#     set_start_value(x[2], 1)
#     @NLobjective(n1, Max, x[1]^2 + x[2]^2)

#     return copied_node, ref = Plasmo._copy_node(n1)
# end

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

end #module

TestAggregatation.run_tests()

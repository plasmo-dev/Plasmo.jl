module TestOptiEdge

using Plasmo
using JuMP
using Ipopt
using Test

function _create_optigraph()
    graph = OptiGraph()

    @optinode(graph, n1)
    @optinode(graph, n2)
    @optinode(graph, n3)
    @optinode(graph, n4)

    @variable(n1, 0 <= x <= 2)
    @variable(n1, 0 <= y <= 3)
    @NLconstraint(n1, x^3 + y <= 4)

    vals = collect(1:5)
    grid = 1:3
    @variable(n2, x >= 1)
    @variable(n2, 0 <= y <= 5)
    @variable(n2, z[1:5] >= 0)
    @variable(n2, a[vals, grid] >= 0)
    @NLconstraint(n2, exp(x) + y <= 7)

    @variable(n3, x[1:5])
    @variable(n4, x <= 1)

    @linkconstraint(graph, ref, n4[:x] == n1[:x])
    @linkconstraint(graph, [t = 1:5], n4[:x] == n2[:z][t])
    @linkconstraint(graph, [i = 1:5], n3[:x][i] == n1[:x])
    @linkconstraint(graph, [j = 1:5, i = 1:3], n2[:a][j, i] == n4[:x])
    @linkconstraint(graph, [i = 1:3], n1[:x] + n2[:z][i] + n3[:x][i] + n4[:x] >= 0)

    @objective(graph, Min, n1[:x] + n2[:x])
    return graph
end

function test_optiedge_1()
    graph = _create_optigraph()
    link_cons = linkconstraints(graph)
    n1 = optinode(graph, 1)
    n4 = optinode(graph, 4)
    e1 = optiedge(graph, 1)

    link_ref = link_cons[1]
    link_con = constraint_object(link_ref)
    @test link_con == link_ref.optiedge.linkconstraints[link_ref.idx]
    @test attached_node(link_con) == n4
    @test shape(link_con) == JuMP.ScalarShape()
    @test name(link_ref) == "ref"

    @test optinodes(link_con) == [n4, n1]
    @test optinodes(link_ref) == [n4, n1]
    @test num_nodes(link_con) == 2

    @test Base.string(e1) == "OptiEdge w/ 1 Constraint(s)"
    @test JuMP.constraint_string(MIME("text/latex"), link_ref) == "ref: n4[:x] - n1[:x] = 0"
    @test JuMP.constraint_string(MIME("text/latex"), link_con) == "n4_{:x} - n1_{:x} = 0"
    @test Base.string(link_con) ==
        "LinkConstraint: n4[:x] - n1[:x], MathOptInterface.EqualTo{Float64}(0.0)"

    @test MOI.is_valid(link_ref) == true
    MOI.delete!(link_ref)
    @test MOI.is_valid(link_ref) == false
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

TestOptiEdge.run_tests()

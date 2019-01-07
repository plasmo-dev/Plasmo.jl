using Plasmo
using JuMP
using GLPKMathProgInterface

tree = ModelTree(solver = BendersSolver(max_iterations = 5,lp_solver = GLPKSolverLP()))

function test_model()
    m1 = Model()
    @variable(m1,x[1:2] >= 0)
    @constraint(m1,x[1] >= 3)
    @objective(m1,Min,x[1] + x[2])
    setsolver(m1,GLPKSolverLP())
    return m1
end

n1 = add_node!(tree,test_model())
n2 = add_node!(tree,test_model())
n3 = add_node!(tree,test_model())

@linkconstraint(tree,[i = 1:2],n1[:x][i] == n2[:x][i])
@linkconstraint(tree,n1[:x][2] == n3[:x][2])

solve(tree)

true

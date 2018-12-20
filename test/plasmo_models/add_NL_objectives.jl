using Plasmo
using JuMP
using Ipopt
using MathProgBase

println("Testing addition of nonlinear objective functions")

m1 = Model()
graph = ModelGraph()
n1 = add_node(graph,m1)
@variable(m1,x[1:2] <= 2)
setvalue(x[1],2)
setvalue(x[2],1)
@NLobjective(m1,Max,x[1]^2 + x[2]^2)

m2 = Model()
n2 = add_node(graph,m2)
@variable(m2,x[1:2] >= 0 )
setvalue(x[1],2)
setvalue(x[2],2)
@NLobjective(m2,Min,x[1]^3 + x[2]^2)


mf = create_jump_graph_model(graph)
mf.solver = IpoptSolver()
solve(mf)

d = JuMP.NLPEvaluator(mf)
MathProgBase.initialize(d,[:ExprGraph])

true

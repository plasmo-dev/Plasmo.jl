using JuMP
using Plasmo
using Ipopt

m1 = Model()
@variable(m1,x)
@variable(m1,y)

@constraint(m1,x+y <= 5)
@constraint(m1,x^2 + y^2 + x*y + 2*x - 5 <= 2)
@NLconstraint(m1,y^3 <= 8)

@objective(m1,Min,x^2+y^2 + 2*x + 3)

m2 = Model()
@variable(m2,x)
@variable(m2,y)

@constraint(m2,x+y <= 5)
@constraint(m2,x^2 + y^2 + x*y + 2*x - 5 <= 2)
@NLconstraint(m2,y^3 <= 8)

@objective(m2,Min,x)

g = PlasmoGraph()
n1 = add_node(g,m1)
n2 = add_node(g,m2)
@linkconstraint(g,n1[:x] == n2[:x])
g.solver = IpoptSolver()
solve(g)

# m = Model()
# m.solver = IpoptSolver()
# @variable(m,x)
# @variable(m,y)
#
# @constraint(m,x+y <= 5)
# @constraint(m,x^2 + y^2 + x*y + 2*x - 5 <= 2)
# @NLconstraint(m,y^3 <= 8)
#
# @NLobjective(m,Min,x^3)
#
# g = PlasmoGraph()
# n1 = add_node(g,m)
# g.solver = IpoptSolver()
# solve(g)

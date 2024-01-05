using JuMP
using Ipopt

m = Model()
@variable(m, x >= 0)
@variable(m, y >= 0)
@constraint(m, ref, x^3 + y^3 >= 0)

jump_func = jump_function(constraint_object(ref))
moi_func = moi_function(constraint_object(ref))


f(x::Real) = x^2
@operator(m, op_f, 1, f)
@expression(m, z, op_f(x))

set_optimizer(m, Ipopt.Optimizer)
JuMP.optimize!(m)
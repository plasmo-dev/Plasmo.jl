using JuMP

m = Model()
@variable(m, x >= 0)
@variable(m, y >= 0)
@constraint(m, ref, x^3 + y^3 >= 0)


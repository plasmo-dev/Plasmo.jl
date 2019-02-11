using JuMP
using Gurobi

time_span = 0:100  #100 time points
delt = 0.1
time_grid = time_span[1]:delt:time_span[end]
time_points = 0:length(time_grid)

yset = 2
ystart = 0
K = 15
tauI = 1
tauD = 0
a = 1.01
b = 1

m = Model(;solver = GurobiSolver())
@variable(m,x[time_points])
@variable(m,u[time_points])
@variable(m,error[time_points])

@constraint(m,initial,x[0] == ystart)
@constraint(m,dynamics[t = time_points[2:end]],(x[t] - x[t-1])/delt == a*x[t] + b*u[t-1])
@constraint(m,err[t = time_points],error[t] == yset - x[t])
@constraint(m,control_law[t = time_points],u[t] == K*((error[t]) + 1/tauI*sum(error[tau]*delt for tau in 1:t)))

solve(m)

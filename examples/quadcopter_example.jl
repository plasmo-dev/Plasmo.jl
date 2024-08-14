# This script requires having v0.6.0+ of Plasmo.jl

using JuMP
using Plasmo
using Ipopt
using Plots
using LinearAlgebra

function Quad(N, dt)
    X_ref = 0:10/N:10;
    dXdt_ref = zeros(N);
    Y_ref = 0:10/N:10;
    dYdt_ref = zeros(N)
    Z_ref = 0:10/N:10;
    dZdt_ref = zeros(N);
    g_ref = zeros(N);
    b_ref = zeros(N);
    a_ref = zeros(N);

    xk_ref = [X_ref, dXdt_ref, Y_ref, dYdt_ref, Z_ref, dZdt_ref, g_ref, b_ref, a_ref];
    grav = 9.8 # m/s^2

    Q = diagm([1, 0, 1, 0, 1, 0, 1, 1, 1]);
    R = diagm([1/10, 1/10, 1/10, 1/10]);

    xk_ref1 = zeros(N,9)
    for i in (1:N)
        for j in 1:length(xk_ref)
            xk_ref1[i,j] = xk_ref[j][i]
        end
    end

    graph = OptiGraph()
    solver = optimizer_with_attributes(Ipopt.Optimizer, "max_iter" => 100)
    set_optimizer(graph, solver)
    @optinode(graph, nodes[1:N])
    for (i, node) in enumerate(nodes)

        # Create state variables
        @variable(node, g)
        @variable(node, b)
        @variable(node, a)

        @variable(node, X)
        @variable(node, Y)
        @variable(node, Z)

        @variable(node, dXdt)
        @variable(node, dYdt)
        @variable(node, dZdt)

        # Create input variables
        @variable(node, C_a)
        @variable(node, wx)
        @variable(node, wy)
        @variable(node, wz)

        # These expressions to simplify the linking constraints later
        @expression(node, d2Xdt2, C_a * (cos(g) * sin(b) * cos(a) + sin(g) * sin(a)))
        @expression(node, d2Ydt2, C_a * (cos(g) * sin(b) * sin(a) + sin(g) * cos(a)))
        @expression(node, d2Zdt2, C_a * cos(g) * cos(b) - grav)

        @expression(node, dgdt, (wx * cos(g) + wy * sin(g)) / (cos(b)))
        @expression(node, dbdt, - wx * sin(g) + wy * cos(g))
        @expression(node, dadt, wx * cos(g) * tan(b) + wy * sin(g) * tan(b) + wz)

        xk = [X, dXdt, Y, dYdt, Z, dZdt, g, b, a] # Array to hold variables

        xk1 = xk .- xk_ref1[i, :] # Array to hold the difference between variable values and their setpoints.

        uk = [C_a, wx, wy, wz]
        @objective(node, Min, (1 / 2 * (xk1') * Q * (xk1) + 1 / 2 * (uk') * R * (uk)) * dt)
    end

    @constraint(nodes[1], nodes[1][:X] == 0)
    @constraint(nodes[1], nodes[1][:Y] == 0)
    @constraint(nodes[1], nodes[1][:Z] == 0)
    @constraint(nodes[1], nodes[1][:dXdt] == 0)
    @constraint(nodes[1], nodes[1][:dYdt] == 0)
    @constraint(nodes[1], nodes[1][:dZdt] == 0)
    @constraint(nodes[1], nodes[1][:g] == 0)
    @constraint(nodes[1], nodes[1][:b] == 0)
    @constraint(nodes[1], nodes[1][:a] == 0)

    for i in 1:(N-1) # iterate through each node except the last
        @linkconstraint(graph, nodes[i+1][:dXdt] == dt*nodes[i][:d2Xdt2] + nodes[i][:dXdt])
        @linkconstraint(graph, nodes[i+1][:dYdt] == dt*nodes[i][:d2Ydt2] + nodes[i][:dYdt])
        @linkconstraint(graph, nodes[i+1][:dZdt] == dt*nodes[i][:d2Zdt2] + nodes[i][:dZdt])

        @linkconstraint(graph, nodes[i+1][:g] == dt*nodes[i][:dgdt] + nodes[i][:g])
        @linkconstraint(graph, nodes[i+1][:b] == dt*nodes[i][:dbdt] + nodes[i][:b])
        @linkconstraint(graph, nodes[i+1][:a] == dt*nodes[i][:dadt] + nodes[i][:a])

        @linkconstraint(graph, nodes[i+1][:X] == dt*nodes[i][:dXdt] + nodes[i][:X])
        @linkconstraint(graph, nodes[i+1][:Y] == dt*nodes[i][:dYdt] + nodes[i][:Y])
        @linkconstraint(graph, nodes[i+1][:Z] == dt*nodes[i][:dZdt] + nodes[i][:Z])
    end

    set_to_node_objectives(graph)

    optimize!(graph);

    return objective_value(graph), graph, xk_ref
end


N = 50
dt = 0.1
objv, graph, xk_ref = Quad(N, dt)
nodes = get_nodes(graph)
# create empty arrays
CAval_array = zeros(length(nodes))
xval_array = zeros(length(nodes))
yval_array = zeros(length(nodes))
zval_array = zeros(length(nodes))

# add values to arrays
for (i, node)  in enumerate(nodes)
    CAval_array[i] = value(node[:C_a])
    xval_array[i] = value(node[:X])
    yval_array[i] = value(node[:Y])
    zval_array[i] = value(node[:Z])
end

xarray = Array{Array}(undef, 2)
xarray[1] = xval_array
xarray[2] = 0:10/(N-1):10

yarray = Array{Array}(undef, 2)
yarray[1] = yval_array
yarray[2] = 0:10/(N-1):10

zarray = Array{Array}(undef, 2)
zarray[1] = zval_array
zarray[2] = 0:10/(N-1):10

plot((1:length(xval_array)), xarray[1:end],
  title = "X value over time",
  xlabel = "Node",
  ylabel = "X Value",
  label = ["Current X position" "X Setpoint"]
)

plot((1:length(yval_array)), yarray[1:end],
  title = "Y value over time",
  xlabel = "Node",
  ylabel = "Y Value",
  label = ["Current X position" "X Setpoint"]
)

plot((1:length(zval_array)), zarray[1:end],
  title = "Z value over time",
  xlabel = "Node",
  ylabel = "Z Value",
  label = ["Current Z position" "Z Setpoint"]
)

time_steps = 2:4:50

N = length(time_steps)
dt = .5
obj_val_N = zeros(N)


for i in 1:length(time_steps)
    timing = @elapsed begin
    objval, graph, xk_ref = Quad(time_steps[i], 10 / time_steps[i]);
    obj_val_N[i] = objval
    end
    println("Done with iteration $i after ", timing, " seconds")
end

Quad_Obj_NN = plot(time_steps, obj_val_N,
title = "Objective Value vs Number of Nodes (N)",
xlabel = "Number of Nodes (N)",
ylabel = "Objective Value",
label  = "Objective Value")


dt_array = .5:.5:5
obj_val_dt = zeros(length(dt_array))

for (i, dt_val) in enumerate(dt_array)
    objval, graph, xk_ref = Quad(N, dt_val);
    obj_val_dt[i] = objval
end

plot(dt_array, obj_val_dt,
    title = "Objective Value vs dt",
    xlabel = "dt value",
    ylabel = "Objective Value",
    legend = :none, color = :black,
    linewidth = 2
)

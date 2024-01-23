# Optimal Control of a Quadcopter

By: Rishi Mandyam

This tutorial notebook is an introduction to the graph-based modeling framework 
Plasmo.jl (PLatform for Scalable Modeling and Optimization) for JuMP 
(Julia for Mathematical Programming).

To begin we will import and use the neccessary packages as shown in the next 
code block.

``using JuMP``
``using Plasmo``
``using Ipopt``
``using Plots``
``using LinearAlgebra``

Establish Setpoints for each timepoint
``X_ref = 0:10/N:10;
    dXdt_ref = 0:10/N:10;
    Y_ref = 0:10/N:10;
    dYdt_ref = 0:10/N:10;
    Z_ref = 0:10/N:10;
    dZdt_ref = 0:10/N:10;
    g_ref = 0:10/N:10;
    b_ref = 0:10/N:10;
    a_ref = 0:10/N:10;``

Define Vector of setpoints
``    xk_ref = [X_ref, dXdt_ref, Y_ref, dYdt_ref, Z_ref, dZdt_ref, g_ref, b_ref, a_ref];``

Define Constants
``grav = 9.8
    C_a = 1``

``Q = diagm([1, 0, 1, 0, 1, 0, 1, 1, 1]);
    R = diagm([1/10, 1/10, 1/10, 1/10]);``

Convert Derivatives using explicit euler's scheme
``xk = [X, dXdt, Y, dYdt, Z, dZdt, g, b, a]``

Transpose Reference Matrix
``xk_ref1 = zeros(N,9)
    for i in (1:N)
        for j in 1:length(xk_ref)
            xk_ref1[i,j] = xk_ref[j][i]
        end
    end``

``uk = [C_a, wx, wy, wz]``

``QuadCopter = Model(Ipopt.Optimizer) # Initialize Model Optimizer # why is model here?
    graph = OptiGraph()  # Initialize Optigraph
    set_optimizer_attribute(graph, "max_iter", 100)
``

``@optinode(graph, nodes[1:N])``

    ``for (i, node) in enumerate(nodes)

        # Create Variables in each of the nodes
        @variable(node, g)
        @variable(node, b)
        @variable(node, a)

        @variable(node, X)
        @variable(node, Y)
        @variable(node, Z)

        @variable(node, dXdt)
        @variable(node, dYdt)
        @variable(node, dZdt)

        @variable(node, C_a)
        
        if i == 1 # Set the initial value of each variable to 0
            @constraint(node, X == 0)
            @constraint(node, Y == 0)
            @constraint(node, Z == 0)
            @constraint(node, dXdt == 0)
            @constraint(node, dYdt == 0)
            @constraint(node, dZdt == 0)
            @constraint(node, g == 0)
            @constraint(node, b == 0)
            @constraint(node, a == 0)
        end
        
        #Establish the variables and nonlinear constraints given in the problem statement
        @variable(node, d2Xdt2)
        @NLconstraint(node, d2Xdt2 == C_a*(cos(g)*sin(b)*cos(a) + sin(g)*sin(a)))
        @variable(node, d2Ydt2)
        @NLconstraint(node, d2Ydt2 == C_a*(cos(g)*sin(b)*sin(a) + sin(g)*cos(a)))
        @variable(node, d2Zdt2)
        @NLconstraint(node, d2Zdt2 == C_a*cos(g)*cos(b) - grav)

        @variable(node, wx)
        @variable(node, wy)
        @variable(node, wz)

        @variable(node, dgdt)
        @NLconstraint(node, dgdt == (wx*cos(g) + wy*sin(g))/(cos(b)))
        @variable(node, dbdt)
        @NLconstraint(node, dbdt == -wx*sin(g) + wy*cos(g))
        @variable(node, dadt)
        @NLconstraint(node, dadt == wx*cos(g)*tan(b) + wy*sin(g)*tan(b) + wz)
        
        xk = [X, dXdt, Y, dYdt, Z, dZdt, g, b, a] # Array to hold variables
        xk1 = xk-xk_ref1[i,:] # Array to hold the difference between variable values and their setpoints.

        uk = [C_a, wx, wy, wz] 
        
        # Establish objective function given in problem statement
        @objective(node, Min, (1/2*(xk1')*Q*(xk1) + 1/2*(uk')*R*(uk)) * dt) #row Q column

    end

    # not a decomposition scheme
    # Add link constraints between nodes using explicit Euler's scheme and problem statement

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
    # Set Optimizer
    set_optimizer(graph, Ipopt.Optimizer);
    set_optimizer_attribute(graph, "max_iter", 700);
    # Call the optimizer
    optimize!(graph);

    return objective_value(graph), nodes, xk_ref;
    end``

# Obtain Objective Values for Varying Numbers of Nodes
    time_steps = 2:4:50

    N = length(time_steps)
    dt = .5
    obj_val_N = zeros(N)
    
    
    for i in 1:length(time_steps)
        timing = @elapsed begin
        objval, nodes = Quad(time_steps[i], 10 / time_steps[i]);
        obj_val_N[i] = objval
        end
        println("Done with iteration $i after ", timing, " seconds")
    end

Plot the Relationship
``plot(time_steps, obj_val_N, title = "Objective Value vs Number of Nodes (N)", xlabel = "Number of Nodes (N)", ylabel = "Objective Value")
``

# Show Graph of Current Value, Control Action, and Setpoint
    ``N = 100
    dt = .1
    objv, nodes = Quad(N, dt)
    
    CAval_array = zeros(length(nodes))
    xval_array = zeros(length(nodes))
    yval_array = zeros(length(nodes))
    zval_array = zeros(length(nodes))
    
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
    
    print(CAval_array)

# Show the Position of the Quadcopter in Relation to its Setpoint

``plot((1:length(xval_array)), xarray[1:end], title = "X value over time", xlabel = "Node (N)", ylabel = "X Value", label = ["Current X position" "X Setpoint"])``
``plot((1:length(yval_array)), yarray[1:end], title = "Y value over time", xlabel = "Node (N)", ylabel = "Y Value", label = ["Current Y position" "Y Setpoint"])``
``plot((1:length(zval_array)), zarray[1:end], title = "Z value over time", xlabel = "Node (N)", ylabel = "Z Value", label = ["Current Z position" "Z Setpoint"])``

# Obtain Objective Values of Varying Levels of Time Discretization

    ``N = 5 # Number of Nodes
    dt_array = .5:.5:3
    obj_val_dt = zeros(length(dt_array))
    
    for (i, dt_val) in enumerate(dt_array)
        objval, nodes = Quad(N, dt_val);
        obj_val_dt[i] = objval
    end

Plot the Relationship
``plot((1:length(obj_val_dt))*dt, obj_val_dt, title = "Objective Value vs dt", xlabel = "dt value", ylabel = "Objective Value", legend = :none, color = :black, linewidth = 2)``

# Conclusion
In this tutorial you were able to:
- successfully used model predictive control to manipulate the postion of a quadcopter
- Show graphical relationships between significant varables.

Next Steps:
- Try adjusting the initial conditions to see how the behavior of the quadcopter changes!


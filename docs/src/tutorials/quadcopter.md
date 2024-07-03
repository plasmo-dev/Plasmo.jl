# Optimal Control of a Quadcopter

By: Rishi Mandyam

This tutorial notebook is an introduction to the graph-based modeling framework 
Plasmo.jl (PLatform for Scalable Modeling and Optimization) for JuMP 
(Julia for Mathematical Programming).

The following problem comes from the paper of Na, Shin,  Anitescu, and Zavala (available [here](https://ieeexplore.ieee.org/stamp/stamp.jsp?arnumber=9840913)).

A quadcopter operates in 3-D space with positions $(x, y, z)$ and angles ($\gamma$, $\beta$, and $\alpha$). 
$g$ is the graviational constant. The set of state variables at time $t$ are treated as $\boldsymbol{x}_t = (x, y, z, \dot{x}, \dot{y}, \dot{z}, \gamma, \beta, \alpha)$. 
The input variables at time $t$ are $\boldsymbol{u}_t = (a, \omega_x, \omega_y, \omega_z)$. 
The quadcopter operates according to the constraints

### 1. To begin we will import and use the necessary packages

```julia 
using JuMP
using Plasmo
using Ipopt
using Plots
using LinearAlgebra
```

### 2. Lets Design our function

This function will:

The function inputs are:
- number of nodes (N)
- time discretization (number of seconds between nodes [dt])

The function outputs are:
- The objective value of the solved graph which is:
    - The sum of all variables in all nodes of the graph
- an array containing each node in the graph (nodes)
- an array with the reference values on each node (xk_ref)

```julia
    function Quad(N, dt)
```

  Establish the setpoints for each timepoint 
  In this example the quadcopter will fly in a linear upward path
  in the positive X, Y, and Z directions
```julia     =#
        X_ref = 0:10/N:10;
        dXdt_ref = 0:10/N:10;
        Y_ref = 0:10/N:10;
        dYdt_ref = 0:10/N:10;
        Z_ref = 0:10/N:10;
        dZdt_ref = 0:10/N:10;
        g_ref = 0:10/N:10;
        b_ref = 0:10/N:10;
        a_ref = 0:10/N:10;
```    
Define the vector of setpoints 

$\boldsymbol{x}_t = (x, y, z, \dot{x}, \dot{y}, \dot{z}, \gamma, \beta, \alpha)$

```julia
        xk_ref = [X_ref, dXdt_ref, Y_ref, dYdt_ref, Z_ref, dZdt_ref, g_ref, b_ref, a_ref];
```    
Define Constants and arrays
```julia
        grav = 9.8 # m/s^2
    
        Q = diagm([1, 0, 1, 0, 1, 0, 1, 1, 1]);
        R = diagm([1/10, 1/10, 1/10, 1/10]);
```

Transpose Reference Matrix
```Julia 
        xk_ref1 = zeros(N,9)
            for i in (1:N)
                for j in 1:length(xk_ref)
                    xk_ref1[i,j] = xk_ref[j][i]
                end
            end
            
        uk = [C_a, wx, wy, wz]
```

Initialize the model optimizer
```Julia 
        QuadCopter = Model(Ipopt.Optimizer)
```

Create the optigraph
```Julia
        graph = OptiGraph()
```

Set the maximum amount of iterations for the optimizer.
```julia
        set_optimizer_attribute(graph, "max_iter", 100)
```
Create N optinodes on the graph
```julia
        @optinode(graph, nodes[1:N])
```

Add the function variables and constraints to each node in the graph
```julia        
        for (i, node) in enumerate(nodes)
    
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
```

Establish the variables, nonlinear constraints, and objective functions given in the problem statement

\begin{align*}
\frac{d^2x}{dt^2} &= a (\cos\gamma \sin \beta \cos \alpha  + \sin \gamma \sin \alpha) \\
\frac{d^2 y}{dt^2} &= a (\cos \gamma \sin \beta \sin \alpha - \sin \gamma \cos \alpha) \\
\frac{d^2 z}{dt^2} &= a \cos \gamma \cos \beta - g \\
\frac{d\gamma}{dt} &= (\omega_x \cos \gamma + \omega_y \sin \gamma) / \cos \beta\\
\frac{d\beta}{dt} &= -\omega_x \sin \gamma + \omega_y \cos \gamma \\
\frac{d\alpha}{dt} &= \omega_x \cos \gamma \tan \beta + \omega_y \sin \gamma \tan \beta + \omega_z
\end{align*}

The input variables at time $t$ are $\boldsymbol{u}_t = (a, \omega_x, \omega_y, \omega_z)$

```julia
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
```            
```julia
              xk = [X, dXdt, Y, dYdt, Z, dZdt, g, b, a] # Array to hold variables
              xk1 = xk-xk_ref1[i,:] # Array to hold the difference between variable values and their setpoints.
              
              uk = [C_a, wx, wy, wz]
``` 
Establish the objective function. This is the same as the stage cost function given in problem statement.

$\phi := \frac{1}{2} (\boldsymbol{x}_t - \boldsymbol{x}^{ref}_t)^\top Q (\boldsymbol{x} - \boldsymbol{x}^{ref}_t) + \boldsymbol{u}^\top R \boldsymbol{u}$ 
where 
$\boldsymbol{x}^{ref}_t$ are the reference values at time $t$.

```julia           

              @objective(node, Min, (1/2*(xk1')*Q*(xk1) + 1/2*(uk')*R*(uk)) * dt) #row Q column
        
          end
```    
Add link constraints between nodes using the explicit Euler's scheme.
```julia
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
```

Set and call the optimizer
```julia

        set_optimizer(graph, Ipopt.Optimizer);
        set_optimizer_attribute(graph, "max_iter", 700);
        
        optimize!(graph);
    end
```
Now that we have created our function to model the behavior of the quadcopter,
we can test it using some example cases.

### Example:
- N = 50 time points
- dt = 0.1 seconds
```julia
N = 100
dt = .1
objv, nodes, xk_ref = Quad(N, dt)

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
```
### Let's see the position of the quadcopter in relation to its setpoint in all three dimentions

```julia
plot((1:length(xval_array)), xarray[1:end], 
  title = "X value over time", 
  xlabel = "Node (N)", 
  ylabel = "X Value", 
  label = ["Current X position" "X Setpoint"])
```
Repeat This process for the Y-position and Z-position

### Your plots should look something like this

<img src = "../assets/Quadcopter_Xpos.png" alt = "drawing" width = "600"/>
<img src = "../assets/Quadcopter_Ypos.png" alt = "drawing" width = "600"/>
<img src = "../assets/Quadcopter_Zpos.png" alt = "drawing" width = "600"/>

### Now that we have solved for the optimal solution, lets explore some other correlations.

Let's see how increasing the number of nodes changes the objective value of the system
```julia
time_steps = 2:4:50

N = length(time_steps)
dt = .5
obj_val_N = zeros(N)


for i in 1:length(time_steps)
    timing = @elapsed begin
    objval, nodes, xk_ref = Quad(time_steps[i], 10 / time_steps[i]);
    obj_val_N[i] = objval
    end
    println("Done with iteration $i after ", timing, " seconds")
end

Quad_Obj_NN = plot(time_steps, obj_val_N, 
    title = "Objective Value vs Number of Nodes (N)", 
    xlabel = "Number of Nodes (N)", 
    ylabel = "Objective Value",
    label  = "Objective Value")
```

<img src = "../assets/Quadcopter_Obj_NN.png" alt = "drawing" width = "600"/>
The plot shows that as you increase the number of nodes, the objective value of the system decreases.

Let's see how changing the dt value changes the objective value of the system.

```julia
N = 5 # Number of Nodes
dt_array = .5:.5:5
obj_val_dt = zeros(length(dt_array))

for (i, dt_val) in enumerate(dt_array)
    objval, nodes = Quad(N, dt_val);
    obj_val_dt[i] = objval
end

# use termination_status(graph)

plot((1:length(obj_val_dt))*dt, obj_val_dt, 
    title = "Objective Value vs dt", 
    xlabel = "dt value", 
    ylabel = "Objective Value", 
    legend = :none, color = :black, 
    linewidth = 2)
```

### Conclusion
In this tutorial you were able to:
- successfully used model predictive control to manipulate the postion of a quadcopter

Next Steps:
- Try adjusting the initial conditions to see how the behavior of the quadcopter changes!




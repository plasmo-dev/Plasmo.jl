
# Optimal PID controller tuning
# Victor M. Zavala
# UW-Madison, 2017

using Ipopt
using Plasmo
using JuMP

function get_scenario_model(s)
    m=Model()
    # variables (states and inputs)
    @variable(m,-2.5<=x[T]<=2.5)
    @variable(m,-2.0<=u[T]<=2.0)
    @variable(m, int[T])
    @variable(m,cost[T])

    # variables (controller design)
    @variable(m, -10<= Kc <=10)
    @variable(m,-100<=tauI<=100)
    @variable(m,-100<=tauD<=1000)

    # constraints
    @constraint(m, eqdyn[t in Tm],(1/tau[s])*(x[t+1]-x[t])/h + x[t+1]== K[s]*u[t+1]+Kd[s]*d[s]);
    @constraint(m, eqcon[t in Tm], u[t+1] == Kc*(xsp[s]-x[t])+ tauI*int[t+1] + tauD*(x[t+1]-x[t])/h);
    @constraint(m, eqint[t in Tm], (int[t+1]-int[t])/h == (xsp[s]-x[t+1]));
    @constraint(m, eqinix,   x[1] == x0[s]);
    @constraint(m, eqinit, int[1] ==  0);
    @constraint(m, eqcost[t in T], cost[t]==(10*(x[t]-xsp[s])^2 + 0.01*u[t]^2));

    # objective function
    @objective(m, Min, (1/(N*NS))*sum(cost[t] for t in T));
    return m
end

# sets
NS=3;       # Number of scenarios
 N=100;     # Number of timesteps
Tf=10;      # Final time
 h=Tf/N;    # Time step
 T=1:N;     # Set of times
Tm=1:N-1;   # Set of times minus one

# set time vector
time=zeros(N);
for t=1:N
 time[t] = h*(t-1);
end

# scenario data
K=zeros(NS);   # system gain
x0=zeros(NS);  # initial state
Kd=zeros(NS);  # disturbance gain
tau=zeros(NS); # time constaint
xsp=zeros(NS); # set-point
d=zeros(NS);   # disturbance

  K[1] =  1.0;
 x0[1] =  0.0;
 Kd[1] =  0.5;
tau[1] =  1.0;
xsp[1] = -1.0;
  d[1] = -1.0;

  K[2] =  1.0;
 x0[2] =  0.0;
 Kd[2] =  0.5;
tau[2] =  1.0;
xsp[2] = -2.0;
  d[2] = -1.0;

  K[3] =  1.0;
 x0[3] =  0.0;
 Kd[3] =  0.5;
tau[3] =  1.0;
xsp[3] =  1.0;
  d[3] = -1.0;

# create two-stage graph moddel
PID = ModelGraph()
master = Model()
master_node = add_node(PID,master)

# add variables to parent node
@variable(master, -10<= Kc <=10)
@variable(master,-100<=tauI<=100)
@variable(master,-100<=tauD<=1000)

# create array of children models
PIDch=Array{ModelNode}(undef,NS)
for s in 1:NS
   # get scenario model
   bl = get_scenario_model(s)
   child = add_node(PID,bl)
   # add children to parent node
   PIDch[s] = child
   # link children to parent variables
   @linkconstraint(PID, bl[:Kc]==Kc)
   @linkconstraint(PID, bl[:tauI]==tauI)
   @linkconstraint(PID, bl[:tauD]==tauD)
end

# solve with Ipopt
setsolver(PID,IpoptSolver())
solve(PID)

@assert round(getvalue(Kc),digits = 4) == 4.3186
@assert round(getvalue(tauI),digits = 4) == 2.2479
@assert round(getvalue(tauD),digits = 4) == -3.1009

true

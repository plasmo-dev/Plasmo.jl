#Simple control example with multiple channels, sampling rates, and delays
using DifferentialEquations
using Plasmo
using Plots
pyplot()

#A function which solves an ode given a workflow and dispatch node
function run_ode_simulation(graph::ComputingGraph,node::ComputeNode)



    a = 1.01; b1 = 1.0;

    t_start = Float64(now(graph))       #the node's current time
    t_next = Float64(getnexttime(graph))   #look it up on the queue

    println("Running simulation from ",now(graph), "to ",t_next)

    if t_next - t_start <= 0
        return true
    end

    tspan = (t_start,t_next)

    u1 = getvalue(node[:u1])
    x0 = node[:x0]

    #A linear ode
    f(x,t,p) = a*x + b1*u1
    prob = ODEProblem(f,x0,tspan)
    sol = DifferentialEquations.solve(prob,Tsit5(),reltol=1e-8,abstol=1e-8)
    x = sol.u[end]  #the final output (i.e. x(t_next))

    node[:x0] = x  #sets the local value for next run
    setvalue(node[:x],x)

    #x_history = node[:x_history]
    push!(node[:x_history],Pair(t_next,x))
    #node[:x_history] = x_history

    setcomputetime(getnodetask(node,:run_simulation),round(t_next - t_start ,digits = 12))
end

#Calculate a PID control law
function calc_pid_controller(graph::ComputingGraph,node::ComputeNode)

    y = getvalue(node[:y])  #expecting a single value

    #yset = node[:yset]
    K = node[:K]
    tauI = node[:tauI]
    tauD = node[:tauD]
    error_history = node[:error_history]  #need error history for integral term

    current_time = now(graph)

    if current_time > 10
        node[:yset] = 1
    end

    current_error = node[:yset] - y

    push!(node[:error_history],Pair(current_time,current_error))

    T = length(error_history)
    #setvalue(node[:error_history],error_history)

    #If there's no error_history
    if length(error_history) >= 2
        tspan = error_history[end][1] - error_history[end-1][1]  #need delt for derivative term
        der = (error_history[end][2] -  error_history[end-1][2])/tspan
        delt = [error_history[1][1] ;diff([error_history[i][1] for i = 1:T])]
        u = K*(current_error + 1/tauI*sum([error_history[i][2]*delt[i] for i = 1:T]) + tauD*der)
    else
        u = K*(current_error)
    end
    #add input limit
    if u < -10
        u = -10
    end
    node[:u] = u

    push!(node[:u_history],Pair(current_time,u))
end

#Create the workflow
graph = ComputingGraph()

#Add the node for the ode simulation
ode_node = addnode!(graph)      #, continuous = true, schedule_delay = 0)   #dispatch node that will reschedule on synchronization
addcomputeattribute!(ode_node,:x,0.0)
addcomputeattribute!(ode_node,:u1,0.0)
addattributes!(ode_node,Dict(:x0 => 0.0,:x_history => Vector{Pair}()))
sim_task = addnodetask!(graph,ode_node,:run_simulation,run_ode_simulation,args = [graph,ode_node],triggered_by = signal_updated(ode_node[:x]))  #this will make the task run continuously
queuesignal!(graph,signal_execute(sim_task),ode_node,0)

#Add the node to do PID calculation
pid_node1 = addnode!(graph)
addcomputeattribute!(pid_node1,:u,0)
addcomputeattribute!(pid_node1,:y,0)
addattributes!(pid_node1,Dict(:yset => 2,:K=>15,:tauI=>1,:tauD=>0.01,:error_history => Vector{Pair}(),:u_history => Vector{Pair}()))
addnodetask!(graph,pid_node1,:control_law,calc_pid_controller,args = [graph,pid_node1],triggered_by = signal_received(pid_node1[:y]))#,compute_time = 0.01)

#e1 will continuously send x --> y (every 0.01 time units)
e1 = connect!(graph,ode_node[:x],pid_node1[:y],delay = 0.01,send_on = signal_sent(ode_node[:x]),send_delay = 0.01)
queuesignal!(graph,signal_communicate(),e1,0.0)

#e2 will send u --> u1 when u is updated
e2 = connect!(graph,pid_node1[:u],ode_node[:u1],delay = 0.01,send_on = signal_updated(pid_node1[:u]))

# #execute the workflow
executor = SerialExecutor(20.0)  #creates a termination event at time 20

println("Executing Simulation")
execute!(graph,executor)  #This will intialize the workflow
#
# # #Plot results
u_history = pid_node1[:u_history]
x_history = ode_node[:x_history]

u_times = [u.first for u in u_history]
u_actions = [u.second for u in u_history]

x_times = [x.first for x in x_history]
x_state = [x.second for x in x_history]

plt = plot()
plot!(plt,x_times,x_state,linewidth = 2)
plot!(plt,u_times,u_actions,linewidth = 2)

# use setaction for fine-grained control of signals and transitions
#setaction(e1,transition,schedule_communicate(frequency))

#Simple control example with multiple channels, sampling rates, and delays
using DifferentialEquations
using Plasmo.PlasmoWorkflows
using Plots
pyplot()

#A function which solves an ode given a workflow and dispatch node
function run_ode_simulation(workflow::Workflow,node::DispatchNode)
    a = 1.01; b1 = 1.0;

    #NOTE Possibly make this a custom kind of node behavior
    t_start = Float64(getcurrenttime(workflow))   #the node's current time
    t_next = Float64(getnexteventtime(workflow))  #look it up on the queue
    tspan = (t_start,t_next)

    u1 = getvalue(getworkflowattribute(node,:u1))
    x0 = node[:x0]

    #A linear ode
    f(x,t,p) = a*x + b1*u1
    prob = ODEProblem(f,x0,tspan)
    sol = DifferentialEquations.solve(prob,Tsit5(),reltol=1e-8,abstol=1e-8)
    x = sol.u[end]  #the final output (i.e. x(t_next))

    setattribute(node,:x0,x)  #sets the local value for next run
    updateattribute(node[:x],x)
    #NOTE Might make sense to have non-connected attributes just be data
    x_history = node[:x_history]
    push!(x_history,Pair(t_next,x))
    setattribute(node,:x_history,x_history)

    setcomputetime(getnodetask(node,:run_simulation),round(t_next - t_start , 5))
    return true  #goes to result
end

#Calculate a PID control law
function calc_pid_controller(workflow::Workflow,node::DispatchNode)

    y = getvalue(getworkflowattribute(node,:y))  #expecting a single value
    yset = node[:yset]
    K = node[:K]
    tauI = node[:tauI]
    tauD = node[:tauD]
    error_history = node[:error_history]  #need error history for integral term
    u_history = node[:u_history]

    current_time = getcurrenttime(workflow)

    if current_time > 10
        setattribute(node,:yset,1)
    end

    current_error = yset - y

    push!(error_history,Pair(current_time,current_error))

    T = length(error_history)
    setattribute(node,:error_history,error_history)

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
    updateattribute(node[:u],u)
    push!(u_history,Pair(current_time,u))
    return true
end

#Create the workflow
workflow = Workflow()

#Add the node for the ode simulation
ode_node = add_dispatch_node!(workflow)#, continuous = true, schedule_delay = 0)   #dispatch node that will reschedule on synchronization
addworkflowattribute!(ode_node,:x,0.0)
addworkflowattribute!(ode_node,:u1,0.0)
addattributes!(ode_node,Dict(:x0 => 0.0,:x_history => Vector{Pair}(),:u1 => 0.0, :x => 0.0))
task = addnodetask!(workflow,ode_node,:run_simulation,run_ode_simulation,args = [workflow,ode_node],continuous = true, schedule_delay = 0.0)
schedulesignal(workflow,Signal(:execute,task),ode_node,0)

#Add the node to do PID calculation
pid_node1 = add_dispatch_node!(workflow)
addworkflowattribute!(pid_node1,:u,0)
addworkflowattribute!(pid_node1,:y,0)
addattributes!(pid_node1,Dict(:yset => 2,:K=>15,:tauI=>1,:tauD=>0.01,:error_history => Vector{Pair}(),:u_history => Vector{Pair}()))
addnodetask!(workflow,pid_node1,:control_law,calc_pid_controller,args = [workflow,pid_node1],triggered_by_attributes = [pid_node1[:y]])


#e1 will continuously send x --> y (every 0.01 time units)
e1 = connect!(workflow,ode_node[:x],pid_node1[:y], continuous = true, send_attribute_updates = false, comm_delay = 0, schedule_delay = 0.1, start_time = 0.01)

#e2 will send u --> u1 when u is updated
e2 = connect!(workflow,pid_node1[:u],ode_node[:u1],continuous = false, comm_delay = 0.01, send_attribute_updates = true)

#execute the workflow
executor = SerialExecutor(20)  #creates a termination event at time 20
# execute!(workflow,executor)  #This will intialize the workflow
#
#
# #Plot results
u_history = pid_node1[:u_history]
x_history = ode_node[:x_history]

u_times = [u.first for u in u_history]
u_actions = [u.second for u in u_history]

x_times = [x.first for x in x_history]
x_state = [x.second for x in x_history]

plt = plot()
plot!(plt,x_times,x_state,linewidth = 2)
plot!(plt,u_times,u_actions,linewidth = 2)

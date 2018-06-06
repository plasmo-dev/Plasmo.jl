#Simple control example with multiple channels, sampling rates, and delays
using DifferentialEquations
using Plasmo
using Plots

#A function which solves an ode given a workflow and dispatch node
#This is a bit convuluted.  Continuous Functions will probably be a special kind of event
#A ContinuousNode could be a convenience for managing this special kind of dispatch
function run_ode_simulation(workflow::Workflow,node::DispatchNode)
    a = 1.01; b1 = 1.0;
    #NOTE Possibly make this a custom kind of node behavior
    t_start = Float64(getcurrenttime(workflow))   #the node's current time
    t_next = Float64(getnexteventtime(workflow))  #look it up on the queue
    tspan = (t_start,t_next)

    u1 = getvalue(getattribute(node,:u1))
    x0 = getvalue(getattribute(node,:x0))

    #A linear ode
    f(x,t,p) = a*x + b1*u1
    prob = ODEProblem(f,x0,tspan)
    sol = DifferentialEquations.solve(prob,Tsit5(),reltol=1e-8,abstol=1e-8)
    x = sol.u[end]  #the final output (i.e. x(t_next))

    setattribute(node,:x0,x)  #sets the local value for next run

    #NOTE Might make sense to have non-connected attributes just be data
    x_history = getvalue(getattribute(node,:x_history))

    push!(x_history,Pair(t_next,x))
    set_node_compute_time(node,round(t_next - t_start , 5))
    return true  #goes to result
end

#Calculate a PID control law
function calc_pid_controller(workflow::Workflow,node::DispatchNode)

    y = getvalue(getattribute(node,:y))  #expecting a single value
    yset = getvalue(getattribute(node,:yset))
    K = getvalue(getattribute(node,:K))
    tauI = getvalue(getattribute(node,:tauI))
    tauD = getvalue(getattribute(node,:tauD))
    error_history = getvalue(getattribute(node,:error_history))  #need error history for integral term
    u_history = getvalue(getattribute(node,:u_history))

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
    #getattribute(node,:u2_history)[current_time] = u
    push!(u_history,Pair(current_time,u))
    return true
end

#Create the workflow
workflow = Workflow()

#Add the node for the ode simulation
ode_node = add_dispatch_node!(workflow, continuous = true, schedule_delay = 0)   #dispatch node that will reschedule on synchronization
addattributes!(ode_node,Dict(:x0 => 0.0,:x_history => Vector{Pair}(),:u1 => 0.0, :u2 => 0.0, :d => 0.0, :x => 0.0))
set_node_task(ode_node,run_ode_simulation)
set_node_task_arguments(ode_node,[workflow,ode_node])
#setinitialsignal(ode_node,Signal(:execute))

schedulesignal(workflow,Signal(:execute),ode_node,0)

#Add the node to do PID calculation
pid_node1 = add_dispatch_node!(workflow)
addattributes!(pid_node1,Dict(:u => 0, :y => 0,:yset => 2,:K=>15,:tauI=>1,:tauD=>0.01,:error_history => Vector{Pair}(),:u_history => Vector{Pair}()))
set_node_task(pid_node1,calc_pid_controller)
set_node_task_arguments(pid_node1,[workflow,pid_node1])

e1 = connect!(workflow,ode_node[:x],pid_node1[:y], continuous = true, send_attribute_updates = false, comm_delay = 0, schedule_delay = 0.01, start_time = 0.01)
e2 = connect!(workflow,pid_node1[:u],ode_node[:u1],continuous = false, comm_delay = 0.02,send_attribute_updates = true)

#execute the workflow
executor = SerialExecutor(20)  #creates a termination event at time 20
#execute!(workflow,executor)  #This will intialize the workflow


# #Plot results
# u_history = getattribute(pid_node1,:u2_history)
# x_history = getattribute(ode_node,:x_history)
#
# u_times = [u.first for u in u_history]
# u_actions = [u.second for u in u_history]
#
# x_times = [x.first for x in x_history]
# x_state = [x.second for x in x_history]
#
# plt = plot()
# plot!(plt,x_times,x_state,linewidth = 2)
# plot!(plt,u_times,u_actions,linewidth = 2)

#Simple control example with multiple channels, sampling rates, and delays
using DifferentialEquations
using PlasmoWorkflows
using PlasmoGraphBase
using Plots

#A function which solves an ode given a workflow and dispatch node
#This is a bit convuluted.  Continuous Functions will probably be a special kind of event
#A ContinuousNode could be a convenience for managing this special kind of dispatch
function run_ode_simulation(workflow::Workflow,node::DispatchNode)
    a = 1.01; b1 = 1.0;
    t_start = Float64(getcurrenttime(workflow))   #the node's current time
    t_next = Float64(getnexteventtime(workflow))  #look it up on the queue
    tspan = (t_start,t_next)

    u1 = Float64(getinput(node,:u1))   #the first input
    x0 = Float64(getattribute(node,:x0))  #get local node state

    #A linear ode
    f(x,t,p) = a*x + b1*u1
    prob = ODEProblem(f,x0,tspan)
    sol = solve(prob,Tsit5(),reltol=1e-8,abstol=1e-8)
    x = sol.u[end]  #the final output (i.e. x(t_next))

    setattribute(node,:x0,x)  #store the state for next run
    push!(getattribute(node,:x_history),Pair(t_next,x))
    set_node_compute_time(node,round(t_next - t_start , 3))
    return x  #goes to result
end

#Calculate a PID control law
function calc_pid_controller(workflow::Workflow,node::DispatchNode)
    y = getinput(node,:y)  #expecting a single value
    yset = getattribute(node,:yset)
    current_time = getcurrenttime(workflow)

    if current_time > 10
        setattribute(node,:yset,1)
    end

    current_error = yset - y
    error_history = getattribute(node,:error_history)  #need error history for integral term

    # if length(error_history) > 1000
    #     shift!(error_history)
    #     append!(error_history,Pair(current_time,current_error))
    # else
    #     push!(error_history,Pair(current_time,current_error))
    # end
    push!(error_history,Pair(current_time,current_error))
    T = length(error_history)
    setattribute(node,:error_history,error_history)

    K = getattribute(node,:K)
    tauI = getattribute(node,:tauI)
    tauD = getattribute(node,:tauD)

    #If there's no error_history
    if length(error_history) >= 2
        tspan = error_history[end][1] - error_history[end-1][1]  #need delt for derivative term
        der = (error_history[end][2] -  error_history[end-1][2])/tspan
        delt = [error_history[1][1] ;diff([error_history[i][1] for i = 1:T])]
        u = K*(current_error + 1/tauI*sum([error_history[i][2]*delt[i] for i = 1:T]) + tauD*der)
    else
        u = K*(current_error)
    end
    if u < -10
        u = -10
    end
    #getattribute(node,:u2_history)[current_time] = u
    push!(getattribute(node,:u2_history),Pair(current_time,u))
    return u
end

#Create the workflow
workflow = Workflow()

#Add the node for the ode simulation
ode_node = add_dispatch_node!(workflow,input_channels = (:u1,:u2,:d),output_channels = (:x))
addattributes!(ode_node,Dict(:x0 => 0,:x_history => Vector{Pair}()))
setinputs(ode_node,u1 = 0,u2 = 0 , d = 0)
settrigger(ode_node,NodeCompleteEvent)  #will re-schedule upon completion (as opposed to scheduling based on inputs).
set_node_function(ode_node,run_ode_simulation)
set_node_function_arguments(ode_node,[workflow,ode_node])               #also see: set_node_function_kwarg
set_result_slot_to_output_channel!(ode_node,1,:x)                   #The result will go into output channel :x

#Add the node to do PID calculation
pid_node1 = add_dispatch_node!(workflow,input_channels = (:y),output_channels = (:u))
settrigger(pid_node1,CommunicationReceivedEvent)                            #this will retrigger the node to its next frequency value
addattributes!(pid_node1,Dict(:K=>15,:tauI=>1,:tauD=>0.01,:error_history=> Vector{Pair}(),:yset=>2,:u2_history => Vector{Pair}()))
set_node_function(pid_node1,calc_pid_controller)
set_node_function_arguments(pid_node1,[workflow,pid_node1])
set_result_slot_to_output_channel!(pid_node1,1,:u)

e1 = connect!(workflow,ode_node,pid_node1,output_channel = :x,input_channel = :y,communication_frequency = 0.01)  #creates an edge that triggers every 5 time points
connect!(workflow,pid_node1,ode_node,output_channel = :u, input_channel = :u1)

#Initialize the workflow
trigger!(workflow,ode_node,0.0)  #trigger the ode node right away
initialize(workflow)

#execute the workflow
executor = SerialExecutor(20)  #creates a termination event at time 100
execute!(workflow,executor)


#Plot results
u_history = getattribute(pid_node1,:u2_history)
x_history = getattribute(ode_node,:x_history)

u_times = [u.first for u in u_history]
u_actions = [u.second for u in u_history]

x_times = [x.first for x in x_history]
x_state = [x.second for x in x_history]

plt = plot()
plot!(plt,x_times,x_state,linewidth = 2)
plot!(plt,u_times,u_actions,linewidth = 2)

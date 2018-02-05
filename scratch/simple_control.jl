#Simple control example with multiple channels, sampling rates, and delays
using DifferentialEquations

function source_gen(workflow::Workflow)
    time = getcurrenttime(workflow)
    u1 = 5*sin(time)
    return u1
end

function ode_sim(workflow::Workflow,node::DispatchNode)
    a = 1.1; b1 = 1; b2 = 1; bd = 1
    # return solve_ode(x0,u1,u2,d,a,b1,b2,bd,tfinal)
    t_start = getprevioustime(workflow)
    t_now = getcurrenttime(workflow)

    u1 = getinput(node,:u1)  #the first input
    u2 = getinput(node,:u2)  #the second input
    d = getinput(node,:d)

    x0 = getstate(node,:x0)
    f(x,u1,u2) = a*x + b1*u1 + b2*u2 + bd*d
    tspan = (t_start,t_now)
    prob = ODEProblem(f,x0,tspan)
    sol = solve(prob,Tsit5(),reltol=1e-8,abstol=1e-8)

    x = sol.u[end]
    setstate(node,:x0,x)

    return x
end

function pid_controller(workflow::Workflow,node::DispatchNode)

    y = getinput(node,:y)  #expecting a single value
    yset = getstate(node,:yset)
    current_error = y - yset

    error_history = getstate(node,:error_history)  #need error history for integral term
    #add some logic about how much history to retain
    if length(error_history) >= 10
        shift!(error_history,current_error)
    else
        push!(error_history,current_error)
    end
    setstate(node,:error_history,error_history)
    setstate(node,:previous_time,getcurrenttime(workflow))

    K = getstate(node,:K)
    tauI = getstate(node,:tauI)
    tauD = getstate(node,:tauD)

    if length(error_history >= 2)
        delt = getcurrenttime(workflow) - getprevioustime(workflow) #need delt for derivative term
        der = (error_history[end] = error_history[end - 1])/delt
    else
        der = 0
    end

    u2 = K*(error_history[end] + 1/tauI*sum(error_history[i]*delt for i in error_history) + tauD*der)

    push!(getstate(node,:u2_history),u2)

    return u2
end

function disturbance()
    return 2
end

#Create the workflow
workflow = Workflow()

#Add the source node
source = add_continous_node(workflow,output_channels = (:u1))
set_function(source,source_gen)     #,workflow)
set_function_argument(source,1,workflow)     #set argument 1
set_result_channel(source,:u1)      #entire result will go into channel :u1


#Add the node for the ode simulation
ode_node = add_continuous_node(workflow,input_channels = (:u1,:u2,:d),output_channels = (:x))
set_function(ode_node,ode_sim)
set_function_argument(ode_node,1,workflow)
set_function_argument(ode_node,2,ode_node)         #also: set_kw_argument
set_result_to_channel(ode_node,:x)                 #The result will go into output channel :x
connect(source,ode_node,output_channel = :u1,input_channel = :u1)    #create communication edge.  output of source is now communicated to ode_node.

#Add the node to do PID calculation
pid_node = add_discrete_node(workflow,input_channels = (:y),output_channels = (:u2))
add_states(pid_node,Dict(:K:1.2,:tauI:1000,:tauD:0,:error_history:[],:yset:2,:u2_history:[]))
set_function(pid_node,pid_controller)

#easy cop out style.  get state values from the node
set_function_argument(pid_node,1,workflow)
set_function_argument(pid_node,2,ode_node)
set_result_to_channel(pid_node,:u1)

#set_input_args(pid_node,pid_node.input, pid_node.args[1])
connect(ode_node,pid_node,output_channel = :x,input_channel = :y,sample_frequency = 5)

#send control signal back to ode simulation
connect(pid_node,ode_node,output_channel = :u2, input_channel = :u2, delay = 1)
#set_input_values(ode_node,Dict(:u2:0))

#Add a disturbance node
disturbance_node = add_continuous_node(workflow)
set_function(disturbance_node,disturbance)
set_inactive(disturbance_node)
connect(disturbance_node,ode_node,output_channel = :d, input_channel = :d)#,start = 0)
#set an initial input channel value
set_input_value(ode_node,:d,0)

#turn on disturbance at time = 5
event = add_event(workflow,set_active,disturbance_node,5)


executor = SerialExecutor(max_time = 30)
execute!(workflow,executor)

#set_time_argument(source,1)  #or map_argument(source,1,workflow)
#map_output(source,1,1)  #first result goes to first output
#exit is automatically the return value

# function pid_controller(error_history::Vector,K,tauI,tauD,delt)
#     der = average(diff(error_history))/delt
#     u2 = K*(error_history[end] + 1/tauI*sum(error_history[i]*delt for i in error_history) + tauD*der)
#     return u2
# end

# set_entry(ode_node,ode_node.input[1],ode_node.args[2])
# set_initial_inputs(ode_node;ode_node.args[4] = 0)

#set_entry(ode_node,ode_node.input[2],ode_node.args[3])#  modifies input arg map

#set_event_time(event,5)  #we aren't worried about interpolating to hit the event exactly yet
#@event workflow set_active(disturbance_node) workflow.current_time >= 5

#@condition pid_node input(pid_node)[1] >= 2             #schedule node only if all conditions pass

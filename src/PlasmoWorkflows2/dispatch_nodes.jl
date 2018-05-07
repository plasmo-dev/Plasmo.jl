#A workflow node attribute.  Has local and global values to manage time synchronization
mutable struct Attribute
    label::Symbol
    local_value::Any
    global_value::Any
end
Attribute() = Attribute(gensym(),nothing,nothing)
Attribute(object::Any) = Attribute(gensym(),object,object)

getlabel(attribute::Attribute) = attribute.label
getlocalvalue(attribute::Attribute) = attribute.local_value
getglobalvalue(attribute::Attribute) = attribute.global_value

function gettransitionactions()
    return schedule_node,run_node_task
end

#Define Transition Actions for a Workflow
function schedule_node(workflow::Workflow,node::DispatchNode)
    delay = 0
    delayed_signal = Signal(:execute)
    signal_now = Signal(:scheduled)
    return Vector(Pair(signal_now,now(workflow),Pair(delayed_signal,delay))
end

#The Manager will broadcast the signal to the queue
function run_node_task(workflow::Workflow,node::DispatchNode)
    try
        run!(node.node_task)  #run the computation task
        setattribute(node,:result,node.node_task.result)
        return Vector(Pair(Signal(:complete),now(workflow)))
    catch
        return Vector(Pair(Signal(:error),now(workflow)))
    end
end

function synchronize_node(workflow::Workflow,node::DispatchNode)
    #Update node global attributes
    compute_time = getcomputetime(node)
    for attribute in getattributes(node)
        queue(Signal(:update_attribute,attribute))
    end
    queue(Signal(:synchronized))
end

#A discrete node gets scheduled on edge triggering
struct DispatchNode <: AbstractDispatchNode  #A Dispatch node
    basenode::BasePlasmoNode
    attributes::Vector{Attribute}
    priority::Int                               #custom node priority when running at same time as another node
    local_time::Float64                         #The node's local clock.  Gets synchronized with the workflow clock on triggers
    compute_time::Float64                       #The time the node takes to complete its task.
    node_task::DispatchFunction                 #the actual function (task) to call
    state_manager::StateManager
    initial_signal::Union{Void,Signal}
end
#Constructor -- Probably need an inner constructor
function DispatchNode()
    basenode = BasePlasmoNode()
    attributes = [Attribute(:result)]
    local_time = 0
    compute_time = 0
    node_task = DispatchFunction()


    state_manager = StateManger()
    setstates(state_manager,[:idle,:scheduled,:computing,:synchronizing,:error,:inactive])
    setstate(state_manager,:idle)
    return DispatchNode(basenode,attributes,0,local_time,compute_time,node_task,state_manager)
end
create_node(graph::Workflow) = DispatchNode()

#Dispatch node transitions
function add_dispatch_node!(workflow::Workflow)
    node = add_node!(workflow)
    state_manager = node.state_manager
    addtransition!(state_manager,State(:idle),Signal(:schedule),State(:scheduled), action = TransitionAction(schedule_node,workflow,node))
    addtransition!(state_manager,State(:idle),Signal(:execute),State(:computing), action = TransitionAction(run_node_task,workflow,node)
    addtransition!(state_manager,State(:computing),Signal(:complete),State(:synchronizing), action = TransitionAction(synchronize_node,workflow,node))
    addtransition!(state_manager,State(:synchronizing),Signal(:synchronized),State(:idle))#, action = synchronized)

    for state in [State(:idle),State(:computing),State(:synchronizing)]
        addtransition!(state_manager,state,Signal(:error),State(:error))
        addtransition!(state_manager,state,Signal(:disable),State(:inactive))
    end

    return node
end

#Continuous node transitions
function add_continuous_node!(workflow::Workflow)
    node = add_node!(workflow)

    return node
end

#Add an attribute.  Update node transitions.
function addattribute!(node::DispatchNode,label::Symbol,attribute::Any)  #e.g. a model
    attribute = Attribute(label,attribute,attribute)
    push!(node.attributes,attribute)
    addtransition!(node.state_manager,State(:synchronizing),Signal(:update_attribute,attribute),State(:synchronizing), action = update_attribute)
end

###########################
# Node Triggers
###########################
getsignals(node::DispatchNode) = getsignals(node.state_manager)
addsignal!(node::DispatchNode,event::DataType) = push!(node.triggers,event)

# #Trigger (schedule) by responding to an event that sends it a trigger
# function send_trigger!(workflow::Workflow,event::AbstractEvent,node::DispatchNode)
#     if typeof(event) in gettriggers(node)
#         trigger!(workflow,node,getcurrenttime(workflow))
#     end
# end

getlocaltime(node::AbstractDispatchNode) = node.local_time
##########################
#Node Result
##########################
getresult(node::AbstractDispatchNode) = getresult(node.dispatch_function)


##########################
#Node Dispatch Function
##########################
set_node_task(node::AbstractDispatchNode,func::Function) = node.dispatch_function = DispatchFunction(func)
set_node_task_arguments(node::AbstractDispatchNode,args::Vector{Any}) = node.dispatch_function.args = args
set_node_task_arguments(node::AbstractDispatchNode,arg::Any) = node.dispatch_function.args = [arg]
set_node_task_kwargs(node::AbstractDispatchNode,kwargs::Dict{Any,Any}) = node.dispatch_function.kwargs = kwargs

set_node_compute_time(node::AbstractDispatchNode,time::Float64) = node.compute_time = time

# set_result_to_output_channel(node::AbstractDispatchNode,i::Int) = node.output.channels[i] = getresult(node)
# set_result_to_output_channel(node::AbstractDispatchNode,s::Symbol) = node.output.channel_labels[s] = getresult(node)

# function set_result_slot_to_output_channel!(node::AbstractDispatchNode,result_slot::Int,channel::Int)
#     output = node.output
#     @assert channel in output.channels
#     pair = Pair(result_slot,channel)
#     if !(pair in node.result_map)
#         push!(node.result_map,pair)
#     end
#     #node.result_map[result_slot] = channel
# end
#
# #Set a result slot to a channel label (and hence id)
# function set_result_slot_to_output_channel!(node::AbstractDispatchNode,result_slot::Int,channel::Symbol)
#     output = node.output
#     @assert channel in keys(output.channel_labels)
#     pair = Pair(result_slot,output.channel_labels[channel])
#     if !(pair in node.result_map)
#         push!(node.result_map,pair)
#     end
#     #node.result_map[result_slot] = output.channel_labels[channel]
# end

########################################
#Update Node Inputs and Outputs
########################################
#update node output using result slot information on the node
# function update_node_output(workflow::Workflow,node::DispatchNode)  #,edge::CommunicationEdge)
#     result = [getresult(node)]            #Get the node result from the dispatch function
#     res_map = node.result_map           #{result_slot => channel_id}
#     output = getoutput(node)            #the node output port
#     for (slot,channel) in res_map
#         #NOTE No edge map if no edges.  Outputs shouldn't require there to be edges
#         #output.data[output.edge_map[channel]] = result[slot]     #might need workflow argument if managing multiple workflows with the same nodes
#         #output.data[channel] = result[slot]
#         setportdata(output,channel,result[slot])
#     end
# end

# #Update node input port using input edge data
# function update_node_input(workflow::Workflow,edge::CommunicationEdge,input_data)
#     node = getconnectedto(workflow,edge)
#     input = getinput(node)
#     channel = getchannel(node.input,edge)
#     setportdata(input,channel,input_data)
# end

########################################
#Connect Nodes with Communication Edges
########################################
function connect!(workflow::Workflow,dnode1::DispatchNode,dnode2::DispatchNode;delay = 0,communication_frequency = 0)
    #is_connected(workflow,dnode1,dnode2) && throw("communication edge already exists between these nodes")

    # #use the first channel on the input port if it's not specified
    # if input_channel == 0
    #     input_channel = 1
    # end
    # #use the first channel on the output port if it's not specified
    # if output_channel == 0
    #     output_channel = 1
    # end
    #
    # if isa(input_channel,Symbol)
    #     input_channel = dnode2.input.channel_labels[input_channel]
    # end
    #
    # if isa(output_channel,Symbol)
    #     output_channel = dnode1.output.channel_labels[output_channel]
    # end

    #Default connection behavior
    comm_edge = add_edge!(workflow,dnode1,dnode2)
    setdelay(comm_edge,delay)
    if communication_frequency > 0
        set_trigger_frequency(comm_edge,communication_frequency)
        settrigger(comm_edge,EdgeTriggerEvent)
    end

    set_channel_to_edge!(dnode1.output,comm_edge,output_channel)
    set_channel_to_edge!(dnode2.input,comm_edge,input_channel)

    return comm_edge
end

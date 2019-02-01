##########################################################
# Define Transition Actions for a Workflow
# The Manager will broadcast the signal to the queue
##########################################################

#################################
# Node Actions
#################################
#Schedule a node to run given a delay
function schedule_node_task(node_task::NodeTask,delay::Float64)
    #delay = getscheduledelay(node_task)
    #signal_now = Signal(:scheduled,node_task)
    delayed_signal = Signal(:execute,node_task)
    return [Pair(signal_now,0),Pair(delayed_signal,delay)]
end

#NOTE Just queue tasks 
function schedule_node_task_during_synchronize(signal::AbstractSignal,node::AbstractDispatchNode,node_task::NodeTask)
    #Put the execute signal in the node queue.  This signal will get evaluated after synchronization
    push!(node.signal_queue,Signal(:execute,node_task))
    return [Pair(Signal(:signal_queued),0)]
end

function pop_node_queue(signal::AbstractSignal,node::AbstractDispatchNode)
    if !isempty(node.signal_queue)
        return_signal = shift!(node.signal_queue)
        return [Pair(return_signal,0)]
    else
        return [Pair(Signal(:nothing),0)]
    end
end

#Run a node task
# function run_node_task(signal::AbstractSignal,workflow::AbstractWorkflow,node::AbstractDispatchNode)
#     #try
#         run!(node.node_task)  #run the computation task
#         setattribute(node,:result,get(node.node_task.result))
#         node.state_manager.local_time = now(workflow) + node.compute_time
#         return [Pair(Signal(:complete),0)]
#     #catch #which error?
#         return [Pair(Signal(:error),0)]
#     #end
# end

function queue_node_task(node_task::NodeTask)
end

function execute_node_task(workflow::AbstractWorkflow,node::AbstractDispatchNode,node_task::NodeTask)
#try
    run!(node_task)
    result_attribute = getworkflowattribute(node,getlabel(node_task))
    updateattribute(result_attribute,node_task.result)        #updates local value
    node.local_time = now(workflow) + node_task.compute_time

    if node.history != nothing
        push!(node.history,(now(workflow),node_task.label,node_task.compute_time))
    end
    return [Pair(Signal(:complete,node_task),0)]
#catch #which error?
    return [Pair(Signal(:error,node_task),0)]
#end
end

#Finalize node task results
function finalize_node_task(node::AbstractDispatchNode,node_task::NodeTask)
    compute_time = getcomputetime(node_task)
    return_signals = Vector{Pair{Signal,Float64}}()

    #for (key,attribute) in getattributes(node)
    #TODO attribute update detection
    for attribute in node.updated_attributes
        if isoutconnected(attribute)
            push!(return_signals,Pair(Signal(:synchronize_attribute,attribute),compute_time))
        end
    end
    node.updated_attributes = Attribute[]
    push!(return_signals,Pair(Signal(:synchronized,node_task),compute_time))
    return return_signals
end

#Synchronize a node attribute
function synchronize_attribute(signal::AbstractSignal,attribute::Attribute)
    attribute.global_value = attribute.local_value
    return [Pair(Signal(:attribute_updated,attribute),0)]
end

##############################
# Edge actions
##############################
#Send an attribute value from source to destination
function communicate(signal::AbstractSignal,workflow::AbstractWorkflow,channel::AbstractChannel)
    from_attribute = channel.from_attribute
    to_attribute= channel.to_attribute
    return_signals = Vector{Pair{AbstractSignal,Float64}}()

    comm_sent_signal = Pair(Signal(:comm_sent,from_attribute),0)
    push!(return_signals,comm_sent_signal)

    comm_received_signal = Pair(DataSignal(:comm_received,to_attribute,getglobalvalue(from_attribute)),channel.delay)
    push!(return_signals,comm_received_signal)

    if channel.history != nothing
        push!(channel.history,(now(workflow),channel.delay))
    end

    return return_signals
end

function schedule_communicate(signal::AbstractSignal,channel::AbstractChannel)
    delayed_signal = Signal(:communicate)
    return [Pair(delayed_signal,channel.schedule_delay)]
end

#Action for receiving an attribute
#attribute gets updated with value from signal
# function receive_attribute(signal::DataSignal,attribute::Attribute)
#     #value = getdata(signal)
#
#     attribute.local_value = value
#     attribute.global_value = value
#     return [Pair(Signal(:attribute_received,attribute),0)]
# end

#Update node attribute with received attribute
function receive_attribute(edge_attribute::Attribute)
    #value = getdata(signal)
    node_attribute = get_destination(edge_attribute)
    value = getvalue(edge_attribute)
    node_attribute.local_value = value
    node_attribute.global_value = value
    return [Pair(Signal(:attribute_received,node_attribute),0)]
end

#function receive_attribute(attribute::Attribute,value::Any)
function update_attribute(signal::DataSignal,attribute::Attribute)
    value = getdata(signal)
    attribute.local_value = value
    attribute.global_value = value
    return [Pair(Signal(:attribute_updated,attribute),0)]
end

#Action for receiving an attribute
# function receive_attribute_while_synchronizing(signal::DataSignal,node::AbstractDispatchNode,attribute::Attribute)
#     push!(node.signal_queue,signal)
#     return [Pair(Signal(:attribute_received,attribute),0)]
# end

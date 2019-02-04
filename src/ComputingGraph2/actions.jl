##########################################################
# Define Transition Actions for a Computing Graph
# Returned signals will be queued in its Signal Queue
##########################################################

#################################
# Node Actions
#################################
#Schedule a node to run given a delay #delay = getscheduledelay(node_task)  #signal_now = Signal(:scheduled,node_task)
function schedule_node_task(graph::AbstractComputingGraph,node_task::NodeTask,delay::Float64)
    execute_signal = Signal(:execute,node_task)
    queuesignal!(graph,execute_signal,now(graph) + delay)
    #return ReturnSignal(execute_signal,delay)
end

function queue_node_task(node_task::NodeTask)
    node = getnode(node_task)
    queuetask!(node,node_task)
    return ReturnSignal()
end

#Put the execute signal in the node queue.  This signal will get evaluated after synchronization
#push!(node.signal_queue,Signal(:execute,node_task))
#return [Pair(Signal(:signal_queued),0)]

function execute_node_task(graph::AbstractComputingGraph,node_task::NodeTask)
    try
        run!(node_task)     #could update node local attributes
        result_attribute = getworkflowattribute(node,getlabel(node_task))
        updateattribute(result_attribute,node_task.result)        #updates local value

        #Advance the node local time
        node.local_time = now(graph) + getcomputetime(node_task)

        if node.history != nothing
            push!(node.history,(now(graph),node_task.label,node_task.compute_time))
        end
        return ReturnSignal(Signal(:finalize,node_task),getcomputetime(node_task))  #[Pair(Signal(:complete,node_task),0)]
    catch #which error?
        return ReturnSignal(Signal(:error,node_task),0)     #[Pair(Signal(:error,node_task),0)]
    end
end

function execute_next_task(graph::AbstractComputingGraph,node::ComputeNode)
    node_task = next_task(node)
    run!(node_task)
end

#Finalize node task results
function finalize_node_task(node_task::NodeTask)
    finalize_time = getfinalizetime(node_task)      #Time spent in finalize state
    return_signals = Vector{ReturnSignal}()
    node = getnode(node_task)
    #for (key,attribute) in getattributes(node)
    for attribute in node.updated_attributes  #NOTE Could try to instead do attribute update detection
        if istrigger(attribute) || if isoutconnected(attribute) #if the attribute can trigger tasks or be sent to other nodes
        #if isoutconnected(attribute)
            push!(return_signals,ReturnSignal(:attribute_updated,attribute),finalize_time)
        end
    end
    node.updated_attributes = Attribute[] #reset updated attributes
    push!(return_signals,ReturnSignal(:back_to_idle,finalize_time))
    return return_signals
end

#Synchronize a node attribute
function finalize_attribute(attribute::Attribute)
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

#NOTE: Shouldn't need this anymore
# function pop_node_queue(signal::AbstractSignal,node::AbstractDispatchNode)
#     if !isempty(node.signal_queue)
#         return_signal = shift!(node.signal_queue)
#         return [Pair(return_signal,0)]
#     else
#         return [Pair(Signal(:nothing),0)]
#     end
# end

# Run a node task
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

# #NOTE Just queue tasks
# function execute_node_task_during_synchronize(node_task::NodeTask)
#     node = getnode(node_task)
#     #Put the execute signal in the node queue.  This signal will get evaluated after synchronization
#
#     push!(node.signal_queue,Signal(:execute,node_task))
#     return [Pair(Signal(:signal_queued),0)]
# end

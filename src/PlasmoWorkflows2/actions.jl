##########################################################
# Define Transition Actions for a Workflow
# The Manager will broadcast the signal to the queue
##########################################################

#################################
# Node Actions
#################################
#Schedule a node to run given a delay
function schedule_node(signal::AbstractSignal,node::DispatchNode)
    delay = getscheduledelay(node)
    signal_now = Signal(:scheduled)
    delayed_signal = Signal(:execute)
    return Vector(Pair(signal_now,0,Pair(delayed_signal,delay))
end

#Run a node task
function run_node_task(signal::AbstractSignal,workflow::Workflow,node::DispatchNode)
    try
        run!(node.node_task)  #run the computation task
        setattribute(node,:result,node.node_task.result)
        return Vector(Pair(Signal(:complete),now(workflow)))
    catch #which error?
        return Vector(Pair(Signal(:error),now(workflow)))
    end
end

#Schedule synchronization
function synchronize_node(signal::AbstractSignal,workflow::Workflow,node::DispatchNode)
    compute_time = getcomputetime(node)
    return_signals = Vector{Pair{Signal,Float64}}()
    for attribute in getattributes(node)
        push!(return_signals,Pair(Signal(:update_attribute,attribute),now(workflow) + compute_time)
    end
    push!(return_signals,Pair(Signal(:synchronized),now(workflow) + compute_time)
    return return_signals
end

#Synchronize a node attribute
function synchronize_attribute(signal::AbstractSignal,workflow::Workflow,attribute::Attribute)
    attribute.global_value = attribute.local_value
    return Vector(Pair(Signal(:attribute_updated,attribute),now(workflow)))
end

##############################
# Edge actions
##############################
#Send an attribute value from source to destination
function communicate(signal::AbstractSignal,workflow::Workflow,channel::Channel)
    from_attribute = channel.from_attribute
    to_attribute= channel.to_attribute
    return_signals = Vector{Pair{Signal,Float64}}()

    comm_sent_signal = Pair(Signal(:comm_sent,from_attribute),now(workflow))
    push!(return_signals,comm_sent_signal)

    comm_received_signal = Pair(DataSignal(:comm_received,to_attribute,getglobalvalue(from_attribute)),now(workflow) + channel.delay)
    push!(return_signals,comm_received_signal)

    return return_signals
end

function schedule_communicate(signal::AbstractSignal,workflow::Workflow,channel::Channel)
    delayed_signal = Signal(:communicate)
    return Vector(Pair(delayed_signal,now(workflow) + channel.comm_delay)
end

#Action for receiving an attribute
#function receive_attribute(attribute::Attribute,value::Any)
function received_attribute(signal::DataSignal,attribute::Attribute,workflow::Workflow)
    value = getdata(signal)
    attribute.local_value = value
    attribute.global_value = value
    return Vector(Pair(Signal(:attribute_received,attribute),now(workflow)))
end

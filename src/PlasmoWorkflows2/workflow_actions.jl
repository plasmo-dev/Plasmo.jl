##########################################################
# Define Transition Actions for a Workflow
# The Manager will broadcast the signal to the queue
##########################################################
function schedule_node(workflow::Workflow,node::DispatchNode)
    delay = 0
    delayed_signal = Signal(:execute)
    signal_now = Signal(:scheduled)
    return Vector(Pair(signal_now,now(workflow),Pair(delayed_signal,delay))
end


function run_node_task(workflow::Workflow,node::DispatchNode)
    try
        run!(node.node_task)  #run the computation task
        setattribute(node,:result,node.node_task.result)
        return Vector(Pair(Signal(:complete),now(workflow)))
    catch #which error?
        return Vector(Pair(Signal(:error),now(workflow)))
    end
end

#Synchronize the node output.
function synchronize_node(workflow::Workflow,node::DispatchNode)
    #Update node global attributes
    compute_time = getcomputetime(node)
    return_signals = Vector{Pair{Signal,Float64}}()
    for attribute in getattributes(node)
        push!(return_signals,Pair(Signal(:update_attribute,attribute),now(workflow) + compute_time)
    end
    push!(return_signals,Pair(Signal(:synchronized),now(workflow) + compute_time)
    return return_signals
end

function update_attribute(workflow::Workflow,attribute::Attribute)
    #Update node global attributes
    attribute.global_value = attribute.local_value
    return Vector(Pair(Signal(:attribute_updated,attribute),now(workflow)))
end

#Send an attribute value from source to destination
function communicate(workflow::Workflow,channel::Channel)
    from_attribute = channel.from_attribute
    to_attribute= channel.to_attribute
    signals = []

    comm_signal = Pair(Signal(:comm_sent,from_attribute),now(workflow))
    push!(signals,comm_signal)

    received_signal = Pair(Signal(:comm_received,[to_attribute,getglobalvalue(from_attribute)]),now(workflow) + channel.delay)
    push!(signals,received_signal)

    return signals
end

function schedule_communicate(workflow::Workflow,channel::Channel)
end

function receive_attribute(workflow::Workflow,attribute::Attribute,value::Any)
    attribute.local_value = value
    attribute.global_value = value

    return Vector(Pair(Signal(:attribute_received,attribute),now(workflow)))
end

# function comm_received(workflow::Workflow,attribute::Attribute)
#     attribute.global_value = attribute.local_value
#     return Vector(Pair(Signal(:attribute_updated,attribute),now(workflow)))
# end

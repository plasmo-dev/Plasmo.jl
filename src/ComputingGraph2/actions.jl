##########################################################
# Define Transition Actions for a Computing Graph
##########################################################

#################################
# Node Actions
#################################
#Schedule a node to run given a delay #delay = getscheduledelay(node_task)  #signal_now = Signal(:scheduled,node_task)
function schedule_node_task(graph::AbstractComputingGraph,node_task::NodeTask,delay::Float64)
    execute_signal = Signal(:execute,node_task)
    node = getnode(node_task)
    queuesignal!(queue,signal,nothing,node,now(graph) + delay,custom_priority = getlocaltime(node))#,priority_map = priority_map)
end

function execute_node_task(graph::AbstractComputingGraph,node_task::NodeTask)
    try

        #detect which attributes were updated

        execute!(node_task)     #Run the task.  This might update attributes (locally)
        result_attribute = getattribute(node,getlabel(node_task))
        setvalue(result_attribute,node_task.result)        #updates local value

        node = getnode(node_task)
        #Advance the node local time
        node.local_time = now(graph) + getcomputetime(node_task)

        if graph.history_on == true
            push!(node.history,(now(graph),node_task.label,getcomputetime(node_task)))
        end

        finalize_signal = Signal(:finalize,node_task)
        queuesignal!(graph,finalize_signal,node,node,now(graph) + getcomputetime(node_task))
    catch #which error?
        queuesignal!(graph,Signal(:error,node_task),node,node,now(graph) + geterrortime(node_task))
    end
end

function execute_next_task(graph::AbstractComputingGraph,node::ComputeNode)
    node_task = next_task!(node)        #pop the next task from the node task queue
    execute_node_task(graph,node_task)
end

function reexecute_node_task(graph::AbstractComputingGraph,node_task::NodeTask)
    try
        #remove finalize signal from queue
        node.local_time = now(graph) - getcomputetime(node_task) #reset node local time

        execute!(node_task)     #Run the task.  This might update attributes (locally)
        result_attribute = getattribute(node,getlabel(node_task))
        updateattribute(result_attribute,node_task.result)        #updates local value
        node = getnode(node_task)
        #Advance the node local time
        node.local_time = now(graph) + getcomputetime(node_task)

        if graph.history_on == true
            push!(node.history,(now(graph),node_task.label,getcomputetime(node_task)))
        end

        #finalize_signal = Signal(:finalize,node_task)
        finalize_signal = finalize(node_task)
        queuesignal!(graph,finalize_signal,node,node,now(graph) + getcomputetime(node_task))
    catch #which error?
        queuesignal!(graph,Signal(:error,node_task),node,node,now(graph) + geterrortime(node_task))
    end
end


#Finalize node task results
function finalize_node_task(graph::AbstractComputingGraph,node_task::NodeTask)
    finalize_time = getfinalizetime(node_task)      #Time spent in finalize state
    node = getnode(node_task)
    queuesignal!(graph,Signal(:back_to_idle),now(graph) + finalize_time)
    for attribute in node.updated_attributes  #NOTE Could try to instead do attribute update detection
        finalizevalue(attribute)
        if isupdatetrigger(attribute) || if isoutconnected(attribute) #if the attribute can trigger tasks or be sent to other nodes
            #update_signal = Signal(:attribute_updated,attribute)
            update_signal = updated(attribute)
            update_targets = getbroadcasttargets(node,update_signal)
            for target in update_targets
                queuesignal!(graph,update_signal,target,node,now(graph) + finalize_time) #NOTE: Might not need finalize time here.  Could just do the update.
            end
        end
    end
    node.updated_attributes = Attribute[] #reset updated attribute list
end

##############################
# Edge actions
##############################
#TODO update these actions to use Edge Attributes
#Send an attribute value from source to destination
function communicate(graph::AbstractComputingGraph,edge::AbstractCommunicationEdge)
    from_attribute = edge.from_attribute
    # to_attribute= edge.to_attribute

    #Queue attribute data on the edge
    push!(edge.attribute_pipeline,EdgeAttribute(from_attribute.value,now(graph)+edge.delay))

    if issendtrigger(from_attribute)
        #sent_signal = Signal(:attribute_sent,from_attribute)
        sent_signal = sent(from_attribute)
        targets = getbroadcasttargets(edge,sent_signal)
        for target in targets
            queuesignal!(graph,sent_signal,target,edge,now(graph))
        end
    end

    receive_target = to_attribute
    #recieve_signal = Signal(:attribute_received,to_attribute)
    receive_signal = receive(edge_attribute)
    queuesignal!(graph,receive_signal,receive_target,edge,now(graph) + edge.delay)

    if graph.history_on == true
        push!(edge.history,(now(graph),edge.delay))
    end
end

schedule_communicate = TransitionAction()
function schedule_communicate(graph::AbstractComputingGraph,edge::AbstractCommunication,delay::Float64)
    signal = Signal(:communicate)
    queuesignal!(graph,signal,edge,nothing,now(graph) + delay)
    #return [Pair(delayed_signal,channel.schedule_delay)]
end

#Update node attribute with received attribute
function receive_attribute(edge_attribute::Attribute)

    node_attribute = get_destination(edge_attribute)
    value = getvalue(edge_attribute)
    node_attribute.local_value = value
    node_attribute.global_value = value

    if isreceivetrigger(node_attribute)
        queuesignal!(received(node_attribute))
    #return [Pair(Signal(:attribute_received,node_attribute),0)]
end

#function receive_attribute(attribute::Attribute,value::Any)
function update_attribute(signal::DataSignal,attribute::Attribute)
    value = getdata(signal)
    attribute.local_value = value
    attribute.global_value = value
    #return [Pair(Signal(:attribute_updated,attribute),0)]
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

#Action for receiving an attribute
#attribute gets updated with value from signal
# function receive_attribute(signal::DataSignal,attribute::Attribute)
#     #value = getdata(signal)
#
#     attribute.local_value = value
#     attribute.global_value = value
#     return [Pair(Signal(:attribute_received,attribute),0)]
# end

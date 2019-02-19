##########################################################
# Define Transition Actions for a Computing Graph
##########################################################
#################################
# Node Actions
#################################
mutable struct NodeAction <: AbstractTransitionAction
    graph::Union{Nothing,AbstractComputingGraph}
    node::Union{Nothing,AbstractComputeNode}
    func::Function                                  #the function to call
    args::Vector{Any}                               #arguments after graph and node
    kwargs::Dict{Symbol,Any}                        #possible kwargs
    #transition::Transition
    #input_signal::Union{Nothing,Signal}
    #function NodeAction(graph::)
end

function addaction!(node::AbstractComputeNode,signal::Signal,state::State,action::NodeAction)
    node.state_manager.action_map[(signal,state)] = action
end

#Run a node action.  Pass the input signal to the action function
function runaction!(input_signal::Signal,action::NodeAction)
    action.func(input_signal,action.graph,action.node,action.args...,action.kwargs...)
end

# function runaction!(action::ActionRunTask)
# end

# function runaction!(signal::Signal,action::NodeAction)
#     action.func(action.graph,action.node,action.args...,action.kwargs...)
# end
# (action.graph != nothing && action.node != nothing) || throw(error("Node action not assigned to a node"))

#Schedule a node task to run given a delay
function schedule_node_task(input_signal::Signal,graph::AbstractComputingGraph,node::AbstractComputeNode,node_task::NodeTask,delay::Float64)
    execute_signal = signal_execute(node_task)
    queue = graph.signalqueue
    queuesignal!(queue,execute_signal,node,now(graph) + delay)
end

action_schedule_node_task(graph::AbstractComputingGraph,node::AbstractComputeNode,node_task::NodeTask,delay::Float64) =
            NodeAction(graph,node,schedule_node_task,[node_task,delay],Dict{Symbol,Any}())

action_schedule_node_task(graph::AbstractComputingGraph,node::AbstractComputeNode,node_task::NodeTask) =
            NodeAction(graph,node,schedule_node_task,[node_task,node_task.schedule_delay],Dict{Symbol,Any}())

#Execute a node task
function execute_node_task(input_signal::Signal,graph::AbstractComputingGraph,node::AbstractComputeNode,node_task::NodeTask)
    #try
        execute!(node_task)     #Run the task.  This might update attributes (locally)
        result_attribute = getcomputeattribute(node,getlabel(node_task))
        setvalue(result_attribute,node_task.result)        #updates local value

        #Advance the node local time
        advancenodetime!(node,now(graph) + getcomputetime(node_task))

        if graph.history_on == true
            push!(node.history,(now(graph),node_task.label,getcomputetime(node_task)))
        end

        finalize_signal = signal_finalize(node_task)
        queuesignal!(graph,finalize_signal,node,now(graph) + getcomputetime(node_task),source = node)
    #catch #which error?
        #TODO Rethrow errors
        #queuesignal!(graph,signal_error(node_task),node,now(graph) + geterrortime(node_task),source = node)
    #end
end
action_execute_node_task(graph::AbstractComputingGraph,node::AbstractComputeNode,node_task::NodeTask) = NodeAction(graph,node,execute_node_task,[node_task],Dict{Symbol,Any}())

#Queue a node task
function queue_node_task(input_signal::Signal,graph::AbstractComputingGraph,node::AbstractComputeNode,node_task::NodeTask)
    DataStructures.enqueue!(node.task_queue,node_task)
end
action_queue_node_task(graph::AbstractComputingGraph,node::AbstractComputeNode,node_task) = NodeAction(graph,node,queue_node_task,[node_task],Dict{Symbol,Any}())

#Execute the next task
function execute_next_task(input_signal::Signal,graph::AbstractComputingGraph,node::AbstractComputeNode)
    #Check for tasks to resume
    #node_task = resume_task!(node)
    #if node_task == nothing
        #Check for queued tasks
    node_task = next_task!(node)        #pop the next task from the node task queue
    if node_task != nothing
        schedule_node_task(input_signal,graph,node,node_task,0.0)
    else
        nothing
    end
    #end
end
action_execute_next_task(graph::AbstractComputingGraph,node::AbstractComputeNode) = NodeAction(graph,node,execute_next_task,[],Dict{Symbol,Any}())

#Finalize node task results
function finalize_node_task(input_signal::Signal,graph::AbstractComputingGraph,node::AbstractComputeNode,node_task::NodeTask)
    finalize_time = getfinalizetime(node_task)      #Time spent in finalize state
    queuesignal!(graph,signal_back_to_idle(),node,now(graph) + finalize_time,source = node)
    for attribute in node.local_attributes_updated
        finalizevalue(attribute)
        if isupdatetrigger(attribute) #If updating the attribute can trigger other actions
            update_signal = signal_updated(attribute)
            update_targets = updatetargets(attribute)
            for target in update_targets
                if isa(target,NodeTask)
                    target = getnode(target)
                end
                queuesignal!(graph,update_signal,target,now(graph) + finalize_time,source = node) #NOTE: Might not need finalize time here.  Could just do the update.
            end
        end
    end
    node.local_attributes_updated = NodeAttribute[] #reset updated attribute list
end
action_finalize_node_task(graph::AbstractComputingGraph,node::AbstractComputeNode,node_task::NodeTask) = NodeAction(graph,node,finalize_node_task,[node_task],Dict{Symbol,Any}())

#
# function suspend_current_task(input_signal::Signal,graph::AbstractComputingGraph,node::AbstractComputeNode,node_task::NodeTask)
#     #suspend the node task and keep track of when it suspended
#     DataStructures.enqueue!(node.suspend_queue,node_task)
#
#     #remove finalize signal
#
#     #execute
#     execute_node_task(input_signal,graph,node,node_task)
# end
#
# function resume_node_task(input_signal::Signal,graph::AbstractComputingGraph,node::AbstractComputeNode)
#     #re-add finalize signal
# end


##############################
# Edge actions
##############################
mutable struct EdgeAction <: AbstractTransitionAction
    graph::Union{Nothing,AbstractComputingGraph}
    edge::Union{Nothing,AbstractCommunicationEdge}
    func::Function                                  #the function to call
    args::Vector{Any}                               #arguments after graph and node
    kwargs::Dict{Symbol,Any}                        #possible kwargs
end

function addaction!(edge::AbstractCommunicationEdge,signal::Signal,state::State,action::NodeAction)
    edge.state_manager.action_map[(signal,state)] = action
end

function runaction!(input_signal::Signal,action::EdgeAction)
    action.func(input_signal,action.graph,action.edge,action.args...,action.kwargs...)
end

#Send an attribute value from source to destination
function communicate(input_signal::Signal,graph::AbstractComputingGraph,edge::AbstractCommunicationEdge)
    from_attribute = edge.from_attribute
    to_attribute= edge.to_attribute

    edge_attribute = addcomputeattribute!(graph,edge,getvalue(from_attribute))  #this will add it to the pipeline

    if issendtrigger(from_attribute)
        sent_signal = signal_sent(from_attribute)
        #targets = getbroadcasttargets(edge,sent_signal)  #NOTE: Think about potentially using some kind of broadcast mapping
        targets = sendtargets(from_attribute)
        for target in targets
            queuesignal!(graph,sent_signal,target,now(graph),source = edge)
        end
    end

    #receive_target = getnode(to_attribute)
    #println("Queueing receive signal")
    receive_signal = signal_receive(edge_attribute)
    queuesignal!(graph,receive_signal,edge,now(graph) + edge.delay,source = edge)

    #TODO Think of a better way to handle edge attribute communication
    #addtransition!(receive_target,state_any(),receive_signal,state_any(),action = action_receive_attribute(graph,edge,edge_attribute))

    graph.history_on && push!(edge.history,(now(graph),edge.delay))
end
action_communicate(graph::AbstractComputingGraph,edge::AbstractCommunicationEdge) = EdgeAction(graph,edge,communicate,[],Dict{Symbol,Any}())


function schedule_communicate(input_signal::Signal,graph::AbstractComputingGraph,edge::AbstractCommunicationEdge,delay::Float64)
    signal = signal_communicate()
    queuesignal!(graph,signal,edge,now(graph) + delay)
end
action_schedule_communicate(graph::AbstractComputingGraph,edge::AbstractCommunicationEdge,delay::Float64) = EdgeAction(graph,edge,schedule_communicate,[delay],Dict{Symbol,Any}())

#Update node attribute with received edge data
function receive_attribute(attribute_signal::Signal,graph::AbstractComputingGraph,edge::AbstractCommunicationEdge)
    edge_attribute = attribute_signal.value
    @assert isa(edge_attribute,EdgeAttribute)

    node_attribute = edge.to_attribute
    receive_node = getnode(node_attribute)
    value = getvalue(edge_attribute)

#    println("receiving ",value," on",node_attribute.node)

    node_attribute.local_value = value   #set local and global values to the received data
    node_attribute.global_value = value
    if isreceivetrigger(node_attribute)  #if the node attribute can trigger a task
        #targets = receivetargets(node_attribute)

        queuesignal!(graph,signal_received(node_attribute),receive_node,now(graph),source = edge)

        #TODO. Add Node to NodeTask and then get node targets
        # targets = receivetargets(node_attribute)
        # for target in targets
        #     queuesignal!(graph,signal_received(node_attribute),target,now(graph),source = edge)
        # end
    end

    removecomputeattribute!(edge::AbstractCommunicationEdge,edge_attribute::EdgeAttribute)
    if isempty(edge.attribute_pipeline)
        queuesignal!(graph,signal_all_received(),edge,now(graph),source = edge)  #Signal that all attributes were received
    end
end
action_receive_attribute(graph::AbstractComputingGraph,edge::AbstractCommunicationEdge) = EdgeAction(graph,edge,receive_attribute,[],Dict{Symbol,Any}())

################################################################################################
# TODO
# function reexecute_node_task(graph::AbstractComputingGraph,node_task::NodeTask)
#     try
#         #remove finalize signal from queue
#         node.local_time = now(graph) - getcomputetime(node_task) #reset node local time
#
#         execute!(node_task)     #Run the task.  This might update attributes (locally)
#         result_attribute = getattribute(node,getlabel(node_task))
#         updateattribute(result_attribute,node_task.result)        #updates local value
#         node = getnode(node_task)
#         #Advance the node local time
#         node.local_time = now(graph) + getcomputetime(node_task)
#
#         if graph.history_on == true
#             push!(node.history,(now(graph),node_task.label,getcomputetime(node_task)))
#         end
#
#         #finalize_signal = Signal(:finalize,node_task)
#         finalize_signal = finalize(node_task)
#         queuesignal!(graph,finalize_signal,node,node,now(graph) + getcomputetime(node_task))
#     catch #which error?
#         queuesignal!(graph,Signal(:error,node_task),node,node,now(graph) + geterrortime(node_task))
#     end
# end
########################################################################################################

# # #IDEA Custom action structs
# mutable struct ScheduleNodeTaskAction <: AbstractTransitionAction
#     graph::Union{Nothing,AbstractComputingGraph}
#     node::Union{Nothing,AbstractComputeNode}
#     func::Function                                  #the function to call
#     args::Vector{Any}                               #arguments after graph and node
#     kwargs::Dict{Symbol,Any}                        #possible kwargs
#     input_signal::Union{Nothing,Signal}
#
#     function ScheduleNodeTask(graph::AbstractComputingGraph,node::ComputeNode)
#         action = new()
#         action.graph = graph
#         action.node = node
#         action.func = schedule_node_task
#         action.args = Vector{Any}() .....
#
#         return action
#
#     end
# end

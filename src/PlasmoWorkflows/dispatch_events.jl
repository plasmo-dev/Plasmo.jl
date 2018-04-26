#Nodes contain Dispatch Functions which get scheduled in a priority queue
@enum event_status idle = 1 scheduled = 2 complete = 3 error = 4



set_idle(event::AbstractEvent) = event.status = idle
set_scheduled(event::AbstractEvent) = event.status = scheduled
set_complete(event::AbstractEvent) = event.status = complete
set_error(event::AbstractEvent) = event.status = error

#Abstract Event functions
gettime(event::AbstractEvent) = event.time
getlocaltime(event::AbstractEvent) = 0
getpriority(event::AbstractEvent) = event.priority
#######################################
#######################################
# Workflow Events
#######################################
#######################################
#Workflow Events are standard events that anything can schedule
mutable struct WorkflowEvent <: AbstractWorkflowEvent
    time::Float64          #the event schedule time
    dfunc::DispatchFunction
    priority::Int
    result::Any            #the result after calling the event
    status::event_status   #the current event status
end
WorkflowEvent(time::Float64) = WorkflowEvent(time,DispatchFunction(),0,Vector{Any}(),Dict{Any,Any}(),Nullable(Any),1)  #idle by default

#Call a workflow event (run its functions with its arguments)
function call!(workflow::Workflow,workflow_event::AbstractWorkflowEvent)
    result = run!(workflow_event.dfunc)  #call the node dispatch function
    workflow_event.status = complete
    return result
end

#######################################
#######################################
# NodeEvents
#######################################
#######################################

################################
# Node Trigger
################################
mutable struct NodeTriggerEvent <: AbstractNodeEvent
    node::AbstractDispatchNode     #the dispatch node this event corresponds to
    time::Float64
    priority::Int
    result::Any
    status::event_status #the current event status
end
NodeTriggerEvent(node::AbstractDispatchNode,time::Float64) = NodeTriggerEvent(node, time,node.priority,node.local_time,idle)
getdispatchnode(node_event::NodeTriggerEvent) = node_event.node
getlocaltime(node_event::AbstractNodeEvent) = node_event.node.local_time

function call!(workflow::Workflow,node_event::NodeTriggerEvent)
    node = node_event.node
    enter_result = node.enter.func(node.enter.args...,node.enter.kwargs...)
    if enter_result == true
        dfunc = node.dispatch_function
        run!(dfunc)
    end
    #update local node time to its latest compute time
    schedule(workflow,node_complete(node,getcurrenttime(workflow) + node.compute_time))     #schedule the update to happen at the actual compute time

    exit_result = node.exit.func(node.exit.args...,node.exit.kwargs...)
    @assert exit_result == true

    #update node status and time
    node.local_time = getcurrenttime(workflow) + node.compute_time
    node_event.status = complete
end

################################
# Node Completed
################################
#Node is complete.  Update its output at a specified time
mutable struct NodeCompleteEvent <: AbstractEvent
    node::AbstractDispatchNode
    time::Float64          #the event schedule time
    priority::Int
    status::event_status   #the current event status
end
NodeCompleteEvent(node::AbstractDispatchNode,time::Float64) = NodeCompleteEvent(node,time,1,idle)
node_complete(node::AbstractDispatchNode,time::Float64) = NodeCompleteEvent(node,time)

function call!(workflow::Workflow,event::NodeCompleteEvent)
    node = event.node
    update_node_output(workflow,node)
    edges_out = PlasmoGraphBase.out_edges(workflow,node)
    for edge in edges_out
        send_trigger!(workflow,event,edge)  #send outgoing triggers to edges
    end
    send_trigger!(workflow,event,node)      #send trigger to node indicating the output was updated (i.e. the node completed in workflow time)
    event.status = complete
end

#######################################
#######################################
# Edge Events
#######################################
#######################################
function send_communication(workflow::Workflow,edge::AbstractCommunicationEdge)
    src = getconnectedfrom(workflow,edge)
    src_output = getoutput(src)
    src_channel = getchannel(src_output,edge)
    src_data = getportdata(src_output,src_channel)
    schedule(workflow,comm_received(edge,getcurrenttime(workflow) + edge.delay,src_data))
end

################################
# Edge Trigger
################################
mutable struct EdgeTriggerEvent <: AbstractEdgeEvent
    edge::AbstractCommunicationEdge
    time::Float64
    priority::Int
    status::event_status    #the current event status
end
EdgeTriggerEvent(edge::AbstractCommunicationEdge,time::Float64) = EdgeTriggerEvent(edge,time,edge.priority,idle)

#getlocaltime(edge_event::AbstractEdgeEvent) = edge_event.edge.local_time

#Define the behavior when the edge event is called (run communication)
function call!(workflow::Workflow,edge_event::EdgeTriggerEvent)
    edge = edge_event.edge
    enter_result = edge.enter.func(edge.enter.args...,edge.enter.kwargs...)
    if enter_result == true
        send_communication(workflow,edge)  #communicate the information to the edge output
    end
    #edge.local_time = getcurrenttime(workflow) + edge.delay
    exit_result = edge.exit.func(edge.exit.args...,edge.exit.kwargs...)  #e.g. could retrigger edge at a later time
    @assert exit_result == true
    send_trigger!(workflow,edge_event,edge,getcurrenttime(workflow) + edge.frequency)
    edge_event.status = complete
end

################################
# Communication Received (By Node)
################################
#Node is complete.  Update its output at a specified time
mutable struct CommunicationReceivedEvent <: AbstractEvent
    edge::AbstractCommunicationEdge
    time::Float64          #the event schedule time
    priority::Int
    data::Any
    status::event_status   #the current event status
end
comm_received(edge::AbstractCommunicationEdge,time::Float64,data) = CommunicationReceivedEvent(edge,time,0,data,idle)

#Send activation triggers to the receiving node and the edge
function call!(workflow::Workflow,event::CommunicationReceivedEvent)
    edge = event.edge
    update_node_input(workflow,edge,event.data)
    node_to = getconnectedto(workflow,edge)
    send_trigger!(workflow,event,node_to)
    send_trigger!(workflow,event,edge)
    event.status = complete
end

#################################
# Event Triggers
#################################
#Trigger edges
function trigger!(workflow::Workflow,edge::AbstractCommunicationEdge,time::Float64)
    edge_event = EdgeTriggerEvent(edge,time)
    schedule(workflow,edge_event)  #schedule edge communication at a given time
end

#Trigger nodes
function trigger!(workflow::Workflow,node::AbstractDispatchNode,time::Float64)
    node_event = NodeTriggerEvent(node,time)
    schedule(workflow,node_event)
end

#Schedule event for the given time.  It goes into the priority queue
function schedule(workflow::Workflow,event::AbstractEvent)
    id = length(workflow.queue) + 1
    priority_value = EventPriorityValue(round(gettime(event),3),getpriority(event),getlocaltime(event),id)
    DataStructures.enqueue!(workflow.queue,event,priority_value)
    event.status = scheduled
end

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
# Signal Events
#######################################
#Workflow Events are standard events that anything can schedule
mutable struct SignalEvent <: AbstractEvent
    time::Float64          #the event schedule time
    signal::Signal
    target::SignalTarget
    priority::Int
    result::Any            #the result after evaluating the signal
    status::event_status   #the event status
end
SignalEvent(time::Float64,signal::Signal,target::SignalTarget) = SignalEvent(time,signal,target,0,Nullable(Any),1)  #idle by default

#Call a workflow event (run its functions with its arguments)
function call!(workflow::Workflow,signal_event::AbstractEvent)
    result = evaluate_signal!(signal_event.signal,signal_event.target)  #call the node dispatch function
    workflow_event.status = complete
    return result
end

#Schedule a signal to occur
function schedule(coordinator::AbstractCoordinator,signal_event::AbstractEvent)
    id = length(workflow.queue) + 1
    priority_value = EventPriorityValue(round(gettime(signal_event),5),getpriority(event),getlocaltime(event),id)
    DataStructures.enqueue!(workflow.queue,signal_event,priority_value)
    signal_event.status = scheduled
end

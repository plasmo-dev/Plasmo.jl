
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
    signal::AbstractSignal
    target::SignalTarget
    priority::Int
    result::Any            #the result after evaluating the signal
    status::event_status   #the event status
end
SignalEvent(time::Float64,signal::AbstractSignal,target::SignalTarget) = SignalEvent(time,signal,target,0,Nullable(Any),1)  #idle by default
SignalEvent(time::Float64,signal::AbstractSignal,target::SignalTarget,priority::Int64) = SignalEvent(time,signal,target,priority,Nullable(Any),1) 

#Call a signal event (run its functions with its arguments)
function call!(coordinator::AbstractSignalCoordinator,signal_event::AbstractEvent)
    result = evaluate_signal!(coordinator,signal_event.signal,signal_event.target)  #call the node dispatch function
    signal_event.result = result
    signal_event.status = complete
    return result
end

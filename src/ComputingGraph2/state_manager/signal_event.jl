##########################
# Priority Value
##########################
struct EventPriorityValue
    time::Float64
    global_priority::Int           #smaller value means higher priority
    local_priority::Float64        #local_time::Float64    #local_time is too specific
    id::Int                 #each key should be unique
end

#Order:
#0. Time -- Lower times come first
#1. Global Priority: All equal by default, can change accordingly
#2. Local Priority
#3. ID: all dispatch functions are unique.  Use this as a tie-breaker for serial processing
function isless(val1::EventPriorityValue,val2::EventPriorityValue) :: Bool
    #check times.  sooner time comes first
    if val1.time < val2.time
        return true
    #if equal times, but different priorities
    elseif val1.time == val2.time && val1.priority < val2.priority
        return true
    #if time and types are equal, use priority
elseif val1.time == val2.time &&  val1.priority  == val2.priority #&& val1.local_time < val2.local_time
        return true
    #if everything is equal, use id numbers
elseif val1.time == val2.time && val1.priority == val2.priority && val1.id < val2.id # &&val1.local_time == val2.local_time && val1.id < val2.id
        return true
    else
        return false
    end
end

#######################################
# Signal Events
#######################################
mutable struct SignalEvent <: AbstractEvent
    time::Float64          #the event schedule time
    signal::AbstractSignal
    source::AbstractStateManager
    target::SignalTarget
    priority::Int
    result::Any            #the result after evaluating the signal
end
SignalEvent(time::Float64,signal::AbstractSignal,target::SignalTarget) = SignalEvent(time,signal,target,0,0,Nullable(Any),1)  #idle by default
SignalEvent(time::Float64,signal::AbstractSignal,target::SignalTarget,priority::Int64) = SignalEvent(time,signal,target,priority,0,Nullable(Any),1)

#Abstract Event functions
gettime(event::AbstractEvent) = event.time
getpriority(event::AbstractEvent) = event.priority

#TODO Consider dropping event result and status
function call!(squeue::AbstractSignalQueue,signal_event::AbstractEvent; priority_map = Dict())
    result = evaluate_signal!(squeue,signal_event.signal,signal_event.target) #,priority_map = priority_map)  #call the node dispatch function
    signal_event.result = result
    #signal_event.status = complete
    return result
end

#status::event_status   #the event status
#localtime::Float64     #Local time of the target
#getlocaltime(sigevent::SignalEvent) = sigevent.localtime

#Call a signal event (run its functions with its arguments)


#@enum event_status idle = 1 scheduled = 2 complete = 3 error = 4

# set_idle(event::AbstractEvent) = event.status = idle
# set_scheduled(event::AbstractEvent) = event.status = scheduled
# set_complete(event::AbstractEvent) = event.status = complete
# set_error(event::AbstractEvent) = event.status = error
#getlocaltime(event::AbstractEvent) = 0

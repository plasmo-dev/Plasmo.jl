##########################
# Priority Value
##########################
struct SignalPriorityValue
    time::Float64                       #earlier times go first
    global_priority::Int                #smaller value means higher priority
    secondary_priority::Float64         #tie-breaker
    id::Int                             #absolute tie-breaker
end

#Order:
#0. Time -- Lower times come first
#1. Global Priority: All equal by default, can change accordingly
#2. Secondary Priority
#3. ID: all dispatch functions are unique.  Use this as a tie-breaker for serial processing
function isless(val1::SignalPriorityValue,val2::SignalPriorityValue) :: Bool
    #check times.  sooner time comes first
    if val1.time < val2.time
        return true
    #if equal times, but different priorities
elseif val1.time == val2.time && val1.global_priority < val2.global_priority
        return true
    #if time and types are equal, use priority
elseif val1.time == val2.time &&  val1.global_priority  == val2.global_priority && val1.secondary_priority < val2.secondary_priority
        return true
    #if everything is equal, use id numbers
elseif val1.time == val2.time && val1.global_priority == val2.global_priority && val1.secondary_priority == val2.secondary_priority && val1.id < val2.id # &&val1.local_time == val2.local_time && val1.id < val2.id
        return true
    else
        return false
    end
end

#######################################
# Signal Events
#######################################
mutable struct SignalEvent <: AbstractSignalEvent
    time::Float64          #the event schedule time
    signal::AbstractSignal
    source::Union{Nothing,SignalTarget}
    target::SignalTarget
    priority::Float64
end
SignalEvent(time::Float64,signal::AbstractSignal,target::SignalTarget) = SignalEvent(time,signal,nothing,target,Float64(0))
SignalEvent(time::Float64,signal::AbstractSignal,source::SignalTarget,target::SignalTarget) = SignalEvent(time,signal,source,target,Float64(0))
#SignalEvent(time::Float64,signal::AbstractSignal,source::SignalTarget,target::SignalTarget,priority::Number) = SignalEvent(time,signal,source,target,Float64(priority))

#Abstract Event functions
gettime(signalevent::AbstractSignalEvent) = signalevent.time
getsecondarypriority(signalevent::AbstractSignalEvent) = signalevent.priority

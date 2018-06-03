##########################
# Priority Value
##########################
struct EventPriorityValue
    time::Float64
    priority::Int          #priority
    local_time::Float64
    id::Int                 #each key should be unique
end
#smaller value means higher priority
#Order:
#0. Time -- Lower times come first
#1. Priority: All equal by default, can change accordingly
#NOTE Might remove this and just use priority. 2. Local Time: Use local time as a tie-breaker if events happen at the same time (e.g. instantaneous sampling).  Priority goes to node or edge that hasn't been pushed to the current time
#3. ID: all dispatch functions are unique.  Use this as a tie-breaker for serial processing
function isless(val1::EventPriorityValue,val2::EventPriorityValue) :: Bool
    #check times.  sooner time comes first
    if val1.time < val2.time
        return true
    #if equal times, but different priorities
    elseif val1.time == val2.time && val1.priority > val2.priority
        return true
    #if time and types are equal, use priority
    elseif val1.time == val2.time &&  val1.priority  == val2.priority && val1.local_time < val2.local_time
        return true
    #if everything is equal, use id numbers
    elseif val1.time == val2.time && val1.priority == val2.priority && val1.local_time == val2.local_time && val1.id < val2.id
        return true
    else
        return false
    end
end

mutable struct SignalCoordinator <: AbstractSignalCoordinator
    time::Float64
    signal_events::Vector{AbstractEvent}
    queue::DataStructures.PriorityQueue{AbstractEvent,EventPriorityValue} #the event queue
end
SignalCoordinator() = SignalCoordinator(0,SignalEvent[],DataStructures.PriorityQueue{AbstractEvent,EventPriorityValue}())
now(coordinator::SignalCoordinator) = coordinator.time
getcurrenttime(coordinator::SignalCoordinator) = now(coordinator)
getqueue(coordinator::SignalCoordinator) = coordinator.queue

#A state manager receives a signal and runs the corresponding transition function which returns new signals
function evaluate_signal!(coordinator::SignalCoordinator,signal::AbstractSignal,SM::StateManager)
    if !(signal in getsignals(SM)) #Check if the signal isn't recognized
        warn("signal $signal not recognized by target $SM")
        return nothing
    end

    #NOTE Need to deal with data signals here
    check_signal = Signal(signal)
    if !(tuple(SM.current_state,check_signal) in keys(SM.transition_map))  #Check if there's no transition from the current state
        warn("no transition for $(SM.current_state) + $signal on $SM")
        return nothing
    end

    transition = SM.transition_map[SM.current_state,check_signal]
    signal_pairs = runtransition!(SM,transition,signal)    #run the transition action.  Returns vector of signal delay pairs
    #signals,delays = run_transition!(transition,signal)
    #Now queue output signals if there are any
    for signal_pair in signal_pairs
        for target in transition.output_signal_targets
            signal = signal_pair.first
            delay = signal_pair.second
            signal_event = SignalEvent(now(coordinator) + delay,signal,target)
            schedulesignal(coordinator,signal_event)
        end
    end
end

function getnexttime(coordinator::SignalCoordinator)
    queue = coordinator.queue
    times = unique(sort([val.time for val in values(queue)]))
    if length(times) == 1
        next_time = times[1]
    else
        next_time = times[2]
    end
    return next_time
end

function getnexteventtime(coordinator::SignalCoordinator)
    queue = coordinator.queue
    times = unique(sort([val.time for val in values(queue)]))
    next_time = times[1]
    return next_time
end
getevents(coordinator::SignalCoordinator) = coordinator.signal_events

#Schedule a signal to occur
function schedulesignal(coordinator::SignalCoordinator,signal_event::AbstractEvent)
    id = length(coordinator.queue) + 1
    priority_value = EventPriorityValue(round(gettime(signal_event),5),getpriority(signal_event),getlocaltime(signal_event),id)
    DataStructures.enqueue!(coordinator.queue,signal_event,priority_value)
    signal_event.status = scheduled
end

function schedulesignal(coordinator::SignalCoordinator,signal::AbstractSignal,target::SignalTarget,time::Number)
    signal_event = SignalEvent(Float64(time),signal,target)
    schedulesignal(coordinator,signal_event)
end

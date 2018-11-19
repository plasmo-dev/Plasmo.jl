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
    elseif val1.time == val2.time && val1.priority < val2.priority
        return true
    #if time and types are equal, use priority
    elseif val1.time == val2.time &&  val1.priority  == val2.priority && val1.local_time < val2.local_time
        return true
    #if everything is equal, use id numbers
    elseif val1.time == val2.time && val1.priority == val2.priority &&  val1.local_time == val2.local_time && val1.id < val2.id
        return true
    else
        return false
    end
end

mutable struct SignalCoordinator <: AbstractSignalCoordinator
    time::Float64
    queue::DataStructures.PriorityQueue{AbstractEvent,EventPriorityValue} #the event queue
end
SignalCoordinator() = SignalCoordinator(0,DataStructures.PriorityQueue{AbstractEvent,EventPriorityValue}())
now(coordinator::SignalCoordinator) = coordinator.time
getcurrenttime(coordinator::SignalCoordinator) = now(coordinator)
getqueue(coordinator::SignalCoordinator) = coordinator.queue

#A state manager receives a signal and runs the corresponding transition function which returns new signals
function evaluate_signal!(coordinator::SignalCoordinator,signal::AbstractSignal,SM::StateManager;priority_map = Dict())
    if (signal in SM.suppressed_signals)
        return nothing
    end

    if !(signal in getsignals(SM)) #Check if the signal isn't recognized
        warn("signal $signal not recognized by target $SM")
        return nothing
    end

    check_signal = Signal(signal)   #Convert data signal to a simple signal
    if !(tuple(SM.current_state,check_signal) in keys(SM.transition_map))  #Or if it's not suppressed
        warn("no transition for $(SM.current_state) + $signal on $SM")
        return nothing
    end

    transition = SM.transition_map[SM.current_state,check_signal]
    signal_pairs = runtransition!(SM,transition,signal)    #run the transition action.  Returns vector of signal delay pairs
    #Now queue output signals if there are any
    for signal_pair in signal_pairs
        for target in transition.output_signal_targets
            signal = signal_pair.first
            delay = signal_pair.second
            schedulesignal(coordinator,signal,target,now(coordinator) + delay,local_time = getlocaltime(target),priority_map = priority_map)
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

#NOTE.  Might update next event time based on queuing.
function getnexteventtime(coordinator::SignalCoordinator)
    queue = coordinator.queue
    times = unique(sort([val.time for val in values(queue)]))
    next_time = times[1]
    return next_time
end
getevents(coordinator::SignalCoordinator) = coordinator.signal_events

function setpriority(signal_event::AbstractEvent,signal::AbstractSignal;priority_map = Dict())
    signal = Signal(signal)  #convert a data signal
    if signal.label in keys(priority_map)
        signal_event.priority = priority_map[signal.label]
    else
        signal_event.priority = 0
    end
end

function setlocaltime(signal_event::AbstractEvent,local_time::Number)
    signal_event.localtime = local_time
end

#Schedule a signal to occur
function schedulesignal(coordinator::SignalCoordinator,signal_event::AbstractEvent)
    id = length(coordinator.queue) + 1
    priority_value = EventPriorityValue(round(gettime(signal_event),5),getpriority(signal_event),getlocaltime(signal_event),id)
    DataStructures.enqueue!(coordinator.queue,signal_event,priority_value)
    signal_event.status = scheduled
end

function schedulesignal(coordinator::SignalCoordinator,signal::AbstractSignal,target::SignalTarget,time::Number;local_time = 0,priority_map = Dict())
    signal_event = SignalEvent(Float64(time),signal,target)
    #TODO Generalize these functions
    setpriority(signal_event,signal,priority_map = priority_map)
    setlocaltime(signal_event,local_time)

    schedulesignal(coordinator,signal_event)
end

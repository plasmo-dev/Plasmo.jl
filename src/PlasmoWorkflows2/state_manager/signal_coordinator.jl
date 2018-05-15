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
#2. Local Time: Use local time as a tie-breaker if events happen at the same time (e.g. instantaneous sampling).  Priority goes to node or edge that hasn't been pushed to the current time
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

struct SignalCoordinator <: AbstractSignalCoordinator
    time::Float64
    signal_events::Vector{AbstractEvent}
    queue::DataStructures.PriorityQueue{AbstractEvent,EventPriorityValue} #the event queue
end
SignalCoordinator() = SignalCoordinator(0,SignalEvent[],DataStructures.PriorityQueue{AbstractEvent,EventPriorityValue}())

#A state manager receives a signal and runs the corresponding transition function which returns new signals
function evaluate_signal!(coordinator::SignalCoordinator,signal::Signal,SM::StateManager)
    if !(signal in getsignals(SM)) #Check if the signal isn't recognized
        return nothing
    end
    if !(tuple(current_state,signal) in keys(SM.transition_map))  #Check if there's no transition from the current state
        return nothing
    end
    transition = SM.transition_map[current_state,signal]
    signals,delays = run_transition!(transition,signal)    #run the transition action.  This may return new signals with delays to go into the coordinator queue
    #signals,delays = run_transition!(transition,signal)
    #Now queue output signals if there are any
    for (signal,delay) in zip(signals,delays)
        for target in transition.targets
            signal_event = SignalEvent(now(coordinator) + delay,signal,target)
            schedule(coordinator,signal_event)
        end
    end
end

function getnexttime(workflow::Workflow)
    queue = workflow.queue
    times = unique(sort([val.time for val in values(queue)]))
    if length(times) == 1
        next_time = times[1]
    else
        next_time = times[2]
    end
    return next_time
end

function getnexteventtime(workflow::Workflow)
    queue = workflow.queue
    times = unique(sort([val.time for val in values(queue)]))
    next_time = times[1]
    return next_time
end
getevents(workflow::Workflow) = workflow.signal_events

#Schedule a signal to occur
function schedule(coordinator::AbstractCoordinator,signal_event::AbstractEvent)
    id = length(workflow.queue) + 1
    priority_value = EventPriorityValue(round(gettime(signal_event),5),getpriority(event),getlocaltime(event),id)
    DataStructures.enqueue!(workflow.queue,signal_event,priority_value)
    signal_event.status = scheduled
end

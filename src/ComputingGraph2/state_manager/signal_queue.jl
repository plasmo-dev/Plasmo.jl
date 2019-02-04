mutable struct SignalQueue <: AbstractSignalQueue
    time::Float64
    global_priority_map::Dict{Symbol,Int}
    queue::DataStructures.PriorityQueue{AbstractEvent,EventPriorityValue} #the event queue
end
SignalQueue() = SignalQueue(0,Dict{Symbol,Int}(),DataStructures.PriorityQueue{AbstractEvent,EventPriorityValue}())

now(queue::SignalQueue) = queue.time
getcurrenttime(queue::SignalQueue) = now(queue)
getqueue(queue::SignalQueue) = queue.queue

#A state manager receives a signal and runs the corresponding transition function which returns new signals
function evaluate_signal!(queue::SignalQueue,signal::AbstractSignal,target::SignalTarget)#;priority_map = Dict())

    SM = getstatemanager(target)

    signal in SM.suppressed_signals && return nothing
    if !(signal in getsignals(SM)) #Check if the signal isn't recognized
        warn("signal $signal not recognized by target $SM")
        return nothing
    end

    #check_signal = Signal(signal)   #Convert data signal to a simple signal
    input_signal = signal
    #if !(tuple(SM.current_state,check_signal) in keys(SM.transition_map))  #Or if it's not suppressed
    if !(hastransition(SM,check_signal))
        warn("no transition for $(SM.current_state) + $signal on $SM")
        return nothing
    end

    #action = SM.action_map[SM.current_state,check_signal]
    #transition = SM.transition_map[SM.current_state,check_signal]
    current_state = SM.current_state
    new_state = SM.transition_map[SM.current_state,input_signal]
    #signal_pairs = runtransition!(SM,transition,signal)    #run the transition action.  Returns vector of return signals
    return_signals = runtransition!(SM,transition)
    source = SM
    #Now queue return signals if there are any
    for return_signal in return_signals
        #for target in transition.output_signal_targets
        for target in SM.broadcast_map[tuple(current_state,input_signal)]
            signal = Signal(return_signal)
            delay = return_signal.delay
            queuesignal!(queue,signal,source,target,now(queue) + delay,local_time = getlocaltime(target))#,priority_map = priority_map)
        end
    end
end

function getnexttime(queue::SignalQueue)
    queue = queue.queue
    times = unique(sort([val.time for val in values(queue)]))
    if length(times) == 1
        next_time = times[1]
    else
        next_time = times[2]
    end
    return next_time
end

#NOTE.  Might update next event time based on queuing.
function getnexteventtime(queue::SignalQueue)
    queue = queue.queue
    times = unique(sort([val.time for val in values(queue)]))
    next_time = times[1]
    return next_time
end
getevents(queue::SignalQueue) = queue.signal_events

function setpriority(signal_event::AbstractEvent,signal::AbstractSignal;priority_map = Dict())
    signal = Signal(signal)  #convert a data signal
    if signal.label in keys(priority_map)
        signal_event.priority = priority_map[signal.label]
    else
        signal_event.priority = 0
    end
end

# function setlocaltime(signal_event::AbstractEvent,local_time::Number)
#     signal_event.localtime = local_time
# end

#Schedule a signal to occur
function queuesignal!(queue::SignalQueue,signal_event::AbstractEvent)
    id = length(queue.queue) + 1
    priority_value = EventPriorityValue(round(gettime(signal_event),5),getpriority(signal_event),getlocaltime(signal_event),id)
    DataStructures.enqueue!(queue.queue,signal_event,priority_value)
    signal_event.status = scheduled
end

function queuesignal!(queue::SignalQueue,signal::AbstractSignal,target::SignalTarget,time::Number;local_time = 0,priority_map = Dict())
    signal_event = SignalEvent(Float64(time),signal,target)
    #TODO Generalize these functions
    setpriority(signal_event,signal,priority_map = priority_map)
    setlocaltime(signal_event,local_time)

    schedulesignal(queue,signal_event)
end

# function schedulesignal(queue::SignalQueue,signal_event::AbstractEvent)
#     id = length(queue.queue) + 1
#     priority_value = EventPriorityValue(round(gettime(signal_event),5),getpriority(signal_event),getlocaltime(signal_event),id)
#     DataStructures.enqueue!(queue.queue,signal_event,priority_value)
#     signal_event.status = scheduled
# end

function schedulesignal(queue::SignalQueue,signal::AbstractSignal,target::SignalTarget,time::Number;local_time = 0,priority_map = Dict())
    signal_event = SignalEvent(Float64(time),signal,target)
    #TODO Generalize these functions
    setpriority(signal_event,signal,priority_map = priority_map)
    setlocaltime(signal_event,local_time)

    schedulesignal(queue,signal_event)
end

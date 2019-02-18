mutable struct SignalQueue <: AbstractSignalQueue
    time::Float64
    signal_priority_order::Vector{AbstractSignal}
    queue::DataStructures.PriorityQueue{AbstractSignalEvent,SignalPriorityValue} #the event queue
end
SignalQueue() = SignalQueue(0.0,Vector{AbstractSignal}(),DataStructures.PriorityQueue{AbstractSignalEvent,SignalPriorityValue}())

#SignalQueue(priority_order::Vector{AbstractSignal}) = SignalQueue(0.0,priority_order,DataStructures.PriorityQueue{AbstractSignalEvent,SignalPriorityValue}())

now(queue::SignalQueue) = queue.time
getcurrenttime(queue::SignalQueue) = now(queue)
getqueue(queue::SignalQueue) = queue.queue

#A state manager receives a signal and runs the corresponding transition function which returns new signals
function evaluate_signal!(queue::SignalQueue,signal::AbstractSignal,target::SignalTarget)
    manager = getstatemanager(target)
    if !(signal in getvalidsignals(manager)) #Check if the signal isn't recognized
        @warn("signal $signal not recognized by target $target in state $(getstate(target))")
        return nothing
    end
    if !(hastransition(manager,getstate(target),signal))
        @warn("no transition for $(getstate(target)) + $signal on $target")
        return nothing
    end
    runtransition!(manager,signal)
    return true
end

evaluate_signal!(squeue::SignalQueue,signal_event::SignalEvent) = evaluate_signal!(squeue,signal_event.signal,signal_event.target)

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
#getevents(queue::SignalQueue) = queue.signal_events

function getglobalpriority(squeue::SignalQueue,signal_event::AbstractSignalEvent)
    signal = signal_event.signal
    if signal in squeue.signal_priority_order
        priority = findall(x -> x == signal,squeue.signal_priority_order)[1]
        return priority
    else
        return 0
    end
end

#Schedule a signal in the signal queue
function queuesignal!(squeue::SignalQueue,signal_event::AbstractSignalEvent)
    id = length(squeue.queue) + 1
    priority_value = SignalPriorityValue(gettime(signal_event),getglobalpriority(squeue,signal_event),getsecondarypriority(signal_event),id)
    DataStructures.enqueue!(squeue.queue,signal_event,priority_value)

    target = getstatemanager(signal_event.target)
    push!(target.active_signals,signal_event)
end

#Methods for different arguments
function queuesignal!(squeue::SignalQueue,signal::AbstractSignal,target::SignalTarget,time::Number;source = nothing,priority::Number = 0.0)
    signal_event = SignalEvent(Float64(time),signal,source,target,Float64(priority))
    queuesignal!(squeue,signal_event)
end
#
# function queuesignal!(squeue::SignalQueue,signal::AbstractSignal,source::SignalTarget,target::SignalTarget,time::Number)
#     signal_event = SignalEvent(Float64(time),signal,source,target)
#     queuesignal!(squeue,signal_event)
# end
#
# function queuesignal!(squeue::SignalQueue,signal::AbstractSignal,source::SignalTarget,target::SignalTarget,time::Number,priority::Number)
#     signal_event = SignalEvent(Float64(time),signal,source,target,priority)
#     queuesignal!(squeue,signal_event)
# end

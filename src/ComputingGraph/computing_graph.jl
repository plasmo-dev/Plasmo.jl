#Computing Graph
mutable struct ComputingGraph <: AbstractComputingGraph
    basegraph::BasePlasmoGraph
    signalqueue::SignalQueue
    history_on::Bool
end
function ComputingGraph()
    basegraph = BasePlasmoGraph(MultiGraph)
    #signal_priority_order =[signal_finalize(),signal_back_to_idle(),signal_receive(),signal_updated(),signal_sent(),signal_received(),signal_communicate(),signal_execute()]
    signal_priority_order =[signal_finalize(),signal_updated(),signal_back_to_idle(),signal_sent(),signal_received(),signal_communicate(),signal_receive(),signal_execute()]
    signalqueue = SignalQueue()
    signalqueue.signal_priority_order = signal_priority_order
    return ComputingGraph(basegraph,signalqueue,true)
end

getsignalqueue(graph::AbstractComputingGraph) = graph.signalqueue
getqueue(graph::AbstractComputingGraph) = getqueue(graph.signalqueue)
stop_graph() = stop_queue()
getcurrenttime(graph::AbstractComputingGraph) = getcurrenttime(graph.signalqueue)
now(graph::AbstractComputingGraph) = now(graph.signalqueue)

function getnexttime(graph::ComputingGraph)
    queue = getqueue(graph)
    times = unique(sort([val.time for val in values(queue)]))
    # if length(times) == 1
    #     next_time = times[1]
    # else
    #     next_time = times[2]    #this will be the next time currently in the queue
    # end
    next_time = times[1]
    return next_time
end

function getnextsignaltime(graph::ComputingGraph)
    queue = getqueue(graph)
    times = unique(sort([val.time for val in values(queue)]))
    next_time = times[1]
    return next_time
end

call!(graph::ComputingGraph,signal_event::SignalEvent) = call!(graph.signal_queue,signal_event)

#Queue Signal methods for computing graph
queuesignal!(graph::ComputingGraph,signal::AbstractSignal,target::SignalTarget,time::Number;source = nothing) =
                    queuesignal!(getsignalqueue(graph),signal,target,time,source = source,priority = getlocaltime(target))


#queuesignal!(graph::ComputingGraph,signal::Signal,source::ComputeNode,target::ComputeNode,time::Number) = queuesignal!(getsignalqueue(graph),signal,source,target,time,priority = getlocaltime(target))

# function schedulesignal(workflow::Workflow,signal::AbstractSignal,target::Union{AbstractDispatchNode,AbstractChannel},time::Number)
#     schedulesignal(workflow.coordinator,signal,getstatemanager(target),time,local_time = getlocaltime(target)#,priority_map = workflow_priority_map)
# end

# global_priority_map = Dict(
# :synchronize_attribute => 0,
# :synchronized => 1,
# :attribute_updated => 2,
# :comm_sent => 3,
# :comm_received => 4,
# :attribute_received => 5,
# :communicate => 5,
# :execute => 6)

#Computing Graph
mutable struct ComputingGraph <: AbstractComputingGraph
    basegraph::BasePlasmoGraph
    signalqueue::SignalQueue
end
function ComputingGraph()
    basegraph = BasePlasmoGraph(MultiGraph)
    signal_priority_order =[signal_finalize(),signal_updated(),signal_sent(),signal_received(),signal_communicate(),signal_execute()]
    signalqueue = SignalQueue()
    signalqueue.signal_priority_order = signal_priority_order
    return ComputingGraph(basegraph,signalqueue)
end

getqueue(graph::AbstractComputingGraph) = getqueue(graph.signalqueue)
stop_graph() = stop_queue()
getcurrenttime(graph::AbstractComputingGraph) = getcurrenttime(graph.signalqueue)
now(graph::AbstractComputingGraph) = now(graph.signalqueue)

function getnexttime(graph::ComputingGraph)
    queue = getqueue(graph)
    times = unique(sort([val.time for val in values(queue)]))
    if length(times) == 1
        next_time = times[1]
    else
        next_time = times[2]    #this will be the next time currently in the queue
    end
    return next_time
end

function getnextsignaltime(graph::ComputingGraph)
    queue = getqueue(graph)
    times = unique(sort([val.time for val in values(queue)]))
    next_time = times[1]
    return next_time
end

call!(graph::ComputingGraph,signal_event::SignalEvent) = call!(graph.signal_queue,signal_event)
queuesignal!(graph::ComputingGraph,signal::AbstractSignal,target::SignalTarget,time::Float64) = queuesignal!(getqueue(graph),signal,target,time,secondary_priority = getlocaltime(target))

# function schedulesignal(workflow::Workflow,signal::AbstractSignal,target::Union{AbstractDispatchNode,AbstractChannel},time::Number)
#     schedulesignal(workflow.coordinator,signal,getstatemanager(target),time,local_time = getlocaltime(target)#,priority_map = workflow_priority_map)
# end

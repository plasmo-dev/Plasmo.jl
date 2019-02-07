#Workflow Graph
mutable struct ComputingGraph <: AbstractComputingGraph
    basegraph::BasePlasmoGraph
    signalqueue::SignalQueue
end
function ComputingGraph()
    graph = new()
    graph.basegraph = BasePlasmoGraph(MultiGraph)

    global_priority_map = Dict(
    :synchronize_attribute => 0,
    :synchronized => 1,
    :attribute_updated => 2,
    :comm_sent => 3,
    :comm_received => 4,
    :attribute_received => 5,
    :communicate => 5,
    :execute => 6)

    graph.signalqueue = SignalQueue()
    return graph
end

# global_priority_map = Dict(
# :synchronize_attribute => 0,
# :synchronized => 1,
# :attribute_updated => 2,
# :comm_sent => 3,
# :comm_received => 4,
# :attribute_received => 5,
# :communicate => 5,
# :execute => 6)

#Signals
updated(attribute::NodeAttribute) = Signal(:updated,attribute)
received(attribute::NodeAttribute) = Signal(:received,attribute)
sent(attribute::NodeAttribute) = Signal(:sent,attribute)
#send(attribute::NodeAttribute) = Signal(:send,attribute)

getqueue(graph::AbstractComputingGraph) = getqueue(graph.signalqueue)
getcurrenttime(graph::AbstractComputingGraph) = getcurrenttime(graph.signalqueue)
now(graph::AbstractComputingGraph) = now(graph.signalqueue)

function getnexttime(graph::ComputingGraph)
    queue = getqueue(graph)
    times = unique(sort([val.time for val in values(queue)]))
    if length(times) == 1
        next_time = times[1]
    else
        next_time = times[2]  #this will be the next time currently in the queue
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

function schedulesignal(workflow::Workflow,signal::AbstractSignal,target::Union{AbstractDispatchNode,AbstractChannel},time::Number)
    schedulesignal(workflow.coordinator,signal,getstatemanager(target),time,local_time = getlocaltime(target),priority_map = workflow_priority_map)
end






#getevents(workflow::Workflow) = workflow.signal_events

##############################
# Schedule Events
##############################
# #Initialize the priority queue
# function initialize(workflow::Workflow)
#     #schedule initial node signals
#     for node in getnodes(workflow)
#         #for signal in getinitialsignal(node)
#         signal = getinitialsignal(node)
#         if signal != nothing
#             schedulesignal(workflow,SignalEvent(0.0,signal,getstatemanager(node)))
#         end
#         #end
#     end
#
#     #Schedule initial edge signals
#     for edge in getedges(workflow)
#         for channel in getchannels(edge)
#             #for signal in getinitialsignal(edge)
#             signal = getinitialsignal(channel)
#             if signal != nothing
#                 schedulesignal(workflow,SignalEvent(0.0,signal,getstatemanager(channel)))
#             end
#         end
#     end
# end

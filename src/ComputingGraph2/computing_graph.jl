#Workflow Graph
mutable struct ComputingGraph <: AbstractComputingGraph
    basegraph::BasePlasmoGraph
    signalqueue::SignalQueue
end
ComutingGraph() =  ComutingGraph(BasePlasmoGraph(DiGraph),SignalQueue())
#getcoordinator(workflow::AbstractWorkflow) = workflow.coordinator
getqueue(graph::AbstractComputingGraph) = getqueue(graph.signalqueue)
getcurrenttime(graph::AbstractComputingGraph) = getcurrenttime(graph.signalqueue)
now(graph::AbstractComputingGraph) = now(graph.signalqueue)

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
    queue = getqueue(workflow)
    times = unique(sort([val.time for val in values(queue)]))
    next_time = times[1]
    return next_time
end
getevents(workflow::Workflow) = workflow.signal_events

##############################
# Schedule Events
##############################
#Initialize the priority queue
function initialize(workflow::Workflow)
    #schedule initial node signals
    for node in getnodes(workflow)
        #for signal in getinitialsignal(node)
        signal = getinitialsignal(node)
        if signal != nothing
            schedulesignal(workflow,SignalEvent(0.0,signal,getstatemanager(node)))
        end
        #end
    end

    #Schedule initial edge signals
    for edge in getedges(workflow)
        for channel in getchannels(edge)
            #for signal in getinitialsignal(edge)
            signal = getinitialsignal(channel)
            if signal != nothing
                schedulesignal(workflow,SignalEvent(0.0,signal,getstatemanager(channel)))
            end
        end
    end
end

call!(workflow::Workflow,signal_event::SignalEvent) = call!(workflow.coordinator,signal_event)


workflow_priority_map = Dict(:synchronize_attribute => 0, :scheduled => 0,:synchronized => 1,:attribute_updated => 2,:comm_sent => 3,:comm_received => 4,:attribute_received => 5, :communicate => 5,:execute => 6)


function schedulesignal(workflow::Workflow,signal::AbstractSignal,target::Union{AbstractDispatchNode,AbstractChannel},time::Number)
    schedulesignal(workflow.coordinator,signal,getstatemanager(target),time,local_time = getlocaltime(target),priority_map = workflow_priority_map)
end

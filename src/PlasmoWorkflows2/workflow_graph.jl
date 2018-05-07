#Workflow Graph
mutable struct Workflow <: AbstractWorkflow
    basegraph::BasePlasmoGraph
    coordinator::SignalCoordinator
end
Workflow() =  Workflow(BasePlasmoGraph(DiGraph),SignalCoordinator())
getcoordinator(workflow::AbstractWorkflow) = workflow.coordinator
getcurrenttime(workflow::AbstractWorkflow) = getcurrenttime(getcoordinator(workflow))

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

##############################
# Schedule Events
##############################
#Initialize the priority queue
function initialize(workflow::Workflow)
    #schedule initial node signals
    for node in getnodes(workflow)
        for (signal,time) in getinitialsignals(node)
            schedule(workflow,SignalEvent(time,signal,node))
        end
    end

    #Schedule initial edge signals
    for edge in getedges(workflow)
        for (signal,time) in getinitialsignals(edge)
            schedule(workflow,SignalEvent(time,signal,edge))
        end
    end

    #schedule any workflow events
    for event in getevents(workflow)
        schedule(workflow,event)  #this
    end
end

#Signals get sent to a coordinator
function run_transition!(transition::Transition)
    signals = transition.action()
    queue(signals)
end

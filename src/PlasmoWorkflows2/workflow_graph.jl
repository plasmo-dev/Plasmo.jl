##########################
# Priority Value
##########################
struct EventPriorityValue
    time::Float64
    priority::Int          #priority
    local_time::Float64
    id::Int                 #each key should be unique
end

#event_type::DataType    #might get rid of this
#getdispatchtype(dispatchvalue::DispatchPriorityValue) = dispatchvalue.event_type

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
    #error("Priority Queue Error.")
end

#Workflow Graph
mutable struct Workflow <: AbstractWorkflow
    basegraph::BasePlasmoGraph
    time::Float64 #::FixedSimTime
    signal_events::Vector{AbstractEvent}
    queue::DataStructures.PriorityQueue{AbstractEvent,EventPriorityValue} #the event queue
end
Workflow() =  Workflow(BasePlasmoGraph(DiGraph),0,AbstractEvent[],DataStructures.PriorityQueue{AbstractEvent,EventPriorityValue}())
getcurrenttime(workflow::AbstractWorkflow) = workflow.time

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

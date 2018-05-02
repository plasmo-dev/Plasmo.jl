
struct Signal
    label::String
    target::StateManager
    value::Any  #Attribute, or other value
end

struct StateManager
    state::Vector{Symbol}
    events::Vector{AbstractEvent}
    signalbroadcastmap::Dict{Signal,Union{DispatchNode,CommunicationEdge}}   #Signals --> Targets
    signaleventmap::Dict{Signal,Event}       #Signals --> Events
end

#run the next item in the schedule
#pop the next item off the queue and add it to Julia's scheduler to run it
function step(workflow::Workflow,executor::AbstractExecutor)
    isempty(workflow.queue) && throw("Queue is empty")
    #isempty(workflow.queue) && error("Queue is empty")
    #look at what's coming next
    (signal, priority_key) = DataStructures.peek(workflow.queue)

    #Dequeue the event function
    DataStructures.dequeue!(workflow.queue)

    #Set the workflow time to the current event's time
    workflow.time = priority_key.time

    task = emit!(executor,workflow,signal)
    #for now, make this block until I figure out how to parallelize
    #task =  run!(executor,workflow,event)  #Different dispatch calls do different things.  Might not want to pass the entire workflow
    #wait(task)  #maybe drop this
 end

#Emit a signal in a workflow
function emit!(executor::SerialExecutor,workflow::Workflow,signal::Signal)
    target = signal.target
    sm = getstatemanager(target)
    receive_signal(sm,signal.label,)
    #send_signal(signal)
end

function run!(executor::SerialExecutor,workflow::Workflow,event::AbstractEvent)
    #task = @schedule call!(workflow,event)
    task = call!(workflow,event)
    return task
end

create_signal("scheduled",)

transition(sm::StateManager)

struct Attribute
    label::Symbol
    local_value::Any   #local to node
    global_value::Any  #actual connected value
end

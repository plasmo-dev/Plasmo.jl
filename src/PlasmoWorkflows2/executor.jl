# function isless(a::EventKey, b::EventKey) :: Bool
#   (a.time < b.time) || (a.time == b.time && a.priority > b.priority) || (a.time == b.time && a.priority == b.priority && a.id < b.id)
# end

# schedule(node_event) => add to queue
# pop from queue => call!(workflow,node_event)
struct StopWorkflow <: Exception
  value :: Any
end
StopWorkflow() = StopWorkflow(nothing)

stop_workflow(ev::AbstractEvent) = throw(StopWorkflow(value(ev)))

##########################
# Executors
##########################
abstract type AbstractExecutor end

###########################
#Serial executor just schedules tasks in the priority queue
###########################
mutable struct SerialExecutor <: AbstractExecutor
    visits::Dict{AbstractDispatchNode,Int}  #number of times each node has been computed
    final_time::Number
end
SerialExecutor() = SerialExecutor(Dict{AbstractDispatchNode,Int}(),0)
SerialExecutor(time) = SerialExecutor(Dict{AbstractDispatchNode,Int}(),time)

#This is the main execution method for an executor
function execute!(workflow::Workflow,executor::AbstractExecutor)  #this should be on the graph really
    # nodes = collectnodes(workflow)                           #get all the nodes
    # executor.visits = Dict(zip(nodes,zeros(length(nodes))))  #set up a map of each node to how many times it has been visited

    while true
        try
            step(workflow,executor)             #step through the priority queue
            if workflow.time >= executor.final_time && workflow.time != 0
                throw(StopWorkflow())
            end
        catch err
            if isa(err,StopWorkflow)
                println("workflow execution complete")
                break
            else
                println("found error")
                rethrow(err)
            end
        end
    end
end

#run the next item in the schedule
#pop the next item off the queue and add it to Julia's scheduler to run it
function step(workflow::Workflow,executor::AbstractExecutor)
    isempty(workflow.queue) && throw("Queue is empty")
    #isempty(workflow.queue) && error("Queue is empty")
    #look at what's coming next
    (signal_event, priority_key) = DataStructures.peek(workflow.queue)

    #Dequeue the event function
    DataStructures.dequeue!(workflow.queue)

    #Set the workflow time to the current event's time
    workflow.time = priority_key.time

    #for now, make this block until I figure out how to parallelize
    #task =  run!(executor,workflow,event)  #Different dispatch calls do different things.  Might not want to pass the entire workflow
    task = run!(executor,workflow,signal_event)
    #wait(task)  #maybe drop this
 end

function run!(executor::SerialExecutor,workflow::Workflow,signal_event::AbstractEvent)
    #task = @schedule call!(workflow,event)
    task = call!(workflow,signal_event)
    return task
end

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
mutable struct SimpleExecutor <: AbstractExecutor
    final_time::Number
end
SimpleExecutor() = SimpleExecutor(0)
#SimpleExecutor(time) = SimpleExecutor(time)

#This is the main execution method for an executor
function execute!(coordinator::SignalCoordinator,executor::AbstractExecutor)  #this should be on the graph really
    while true
        try
            step(coordinator,executor)             #step through the priority queue
            if coordinator.time >= executor.final_time && coordinator.time != 0
                throw(StopWorkflow())
            end
        catch err
            if isa(err,StopWorkflow)
                println("coordinator complete")
                break
            else
                println("found error")
                rethrow(err)
            end
        end
    end
end


function step(coordinator::SignalCoordinator)
    isempty(getqueue(coordinator)) && throw("Queue is empty")
    (signal_event, priority_key) = DataStructures.peek(coordinator.queue)
    #Dequeue the event function
    DataStructures.dequeue!(getqueue(coordinator))
    coordinator.time = priority_key.time
    task = run!(coordinator,signal_event)
end

#run the next item in the schedule with the given executor
function step(coordinator::SignalCoordinator,executor::AbstractExecutor)
    isempty(getqueue(coordinator)) && throw("Queue is empty")
    #isempty(workflow.queue) && error("Queue is empty")
    #look at what's coming next
    (signal_event, priority_key) = DataStructures.peek(coordinator.queue)

    #Dequeue the event function
    DataStructures.dequeue!(getqueue(coordinator))

    #Set the workflow time to the current event's time
    coordinator.time = priority_key.time

    #for now, make this block until I figure out how to parallelize
    #task =  run!(executor,workflow,event)  #Different dispatch calls do different things.  Might not want to pass the entire workflow
    task = run!(executor,coordinator,signal_event)
    #wait(task)  #maybe drop this
 end



function run!(executor::SimpleExecutor,coordinator::SignalCoordinator,signal_event::AbstractEvent)
    #task = @schedule call!(workflow,event)
    task = call!(coordinator,signal_event)
    return task
end

function run!(coordinator::SignalCoordinator,signal_event::AbstractEvent)
    task = call!(coordinator,signal_event)
    return task
end

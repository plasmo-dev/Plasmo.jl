struct StopWorkflow <: Exception
  value :: Any
end
StopWorkflow() = StopWorkflow(nothing)
stop_workflow(event::AbstractEvent) = throw(StopWorkflow(value(event)))

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
function execute!(coordinator::SignalCoordinator,executor::AbstractExecutor;priority_map = Dict())  #this should be on the graph really
    while true
        try
            step(coordinator,executor,priority_map = priority_map)             #step through the priority queue
            if coordinator.time >= executor.final_time && coordinator.time != 0
                throw(StopWorkflow())
            end
            #TODO Check termination conditions

        catch err
            if isa(err,StopWorkflow)
                println("Execution complete")
                break
            else
                println("Found error")
                rethrow(err)
            end
        end
    end
end

function step(coordinator::SignalCoordinator;priority_map = Dict())
    isempty(getqueue(coordinator)) && throw(StopWorkflow("Queue is Empty"))
    (signal_event, priority_key) = DataStructures.peek(coordinator.queue)
    #Dequeue the event function
    DataStructures.dequeue!(getqueue(coordinator))
    coordinator.time = priority_key.time
    task = run!(coordinator,signal_event,priority_map = priority_map)
end

#run the next item in the schedule with the given executor
function step(coordinator::SignalCoordinator,executor::AbstractExecutor;priority_map = Dict())
    isempty(getqueue(coordinator)) && throw(StopWorkflow("Queue is Empty"))
    #isempty(workflow.queue) && error("Queue is empty")
    #look at what's coming next
    (signal_event, priority_key) = DataStructures.peek(coordinator.queue)

    #Dequeue the event function
    DataStructures.dequeue!(getqueue(coordinator))

    #Set the workflow time to the current event's time
    coordinator.time = priority_key.time

    #for now, make this block until I figure out how to parallelize
    task = run!(executor,coordinator,signal_event,priority_map = priority_map)


    #wait(task)  #maybe drop this
 end

function run!(executor::SimpleExecutor,coordinator::SignalCoordinator,signal_event::AbstractEvent;priority_map = Dict())
    #task = @schedule call!(workflow,event)
    task = call!(coordinator,signal_event,priority_map = priority_map)
    return task
end

function run!(coordinator::SignalCoordinator,signal_event::AbstractEvent;priority_map = Dict())
    task = call!(coordinator,signal_event,priority_map = priority_map)
    return task
end

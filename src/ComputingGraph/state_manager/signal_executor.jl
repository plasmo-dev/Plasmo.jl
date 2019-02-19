struct QueueComplete <: Exception
  value :: Any
end
QueueComplete() = QueueComplete(nothing)

struct QueueStopped <: Exception
  value :: Any
end
QueueStopped() = QueueStopped(nothing)
stop_queue() = QueueStopped()
#stop_workflow(event::AbstractEvent) = throw(StopWorkflow(value(event)))

##########################
# Executors
##########################
abstract type AbstractExecutor end

###########################
#Simple executor just schedules tasks in the priority queue
###########################
mutable struct SimpleExecutor <: AbstractExecutor
    final_time::Float64
end
SimpleExecutor() = SimpleExecutor(Float64(200))
SimpleExecutor(time::Number) = SimpleExecutor(Float64(time))

#Run signal events
run!(executor::SimpleExecutor,squeue::SignalQueue,signal_event::AbstractSignalEvent) = evaluate_signal!(squeue,signal_event)
run!(squeue::SignalQueue,signal_event::AbstractSignalEvent) = evaluate_signal!(squeue,signal_event)

#This is the main execution method for an executor
function execute!(queue::SignalQueue,executor::AbstractExecutor)#;priority_map = Dict())  #this should be on the graph really
    while true
        try
            step(queue,executor)  #step through the priority queue

            if queue.time >= executor.final_time && queue.time != 0
                throw(QueueComplete("QueueComplete"))
            end

            #TODO Check termination conditions

        catch err
            if isa(err,QueueComplete)
                println(err)
                println("Execution complete: ",err.value)
                break
            else
                println("Signal Queue Terminated for unknown reason")
                rethrow(err)
            end
        end
    end
end

function step(squeue::SignalQueue)
    isempty(squeue.queue) && throw(QueueComplete("Queue is Empty"))
    (signal_event, priority_key) = DataStructures.peek(squeue.queue)
    DataStructures.dequeue!(squeue.queue)   #Dequeue the event function
    squeue.time = priority_key.time
    run!(squeue,signal_event)
end

function debug_step(squeue::SignalQueue)
    isempty(squeue.queue) && throw(QueueComplete("Queue is Empty"))
    (signal_event, priority_key) = DataStructures.peek(squeue.queue)
    println(signal_event)
    DataStructures.dequeue!(squeue.queue)   #Dequeue the event function
    squeue.time = priority_key.time
    run!(squeue,signal_event)
end

#run the next item in the schedule with the given executor
function step(squeue::SignalQueue,executor::AbstractExecutor)
    isempty(squeue.queue) && throw(QueueComplete("Queue is Empty"))

    #look at what's coming next
    (signal_event, priority_key) = DataStructures.peek(squeue.queue)

    #Dequeue the event function
    DataStructures.dequeue!(squeue.queue)

    #Set the workflow time to the current event's time
    squeue.time = priority_key.time

    #NOTE A different executor might have to do synchronization
    run!(executor,squeue,signal_event)

    #wait(task)  #maybe drop this

 end

function advance(squeue::SignalQueue,executor::AbstractExecutor,time::Number)
    while squeue.time <= time
        try
            step(squeue,executor)
            if squeue.time >= executor.final_time && squeue.time != 0
                throw(StopQueue())
            end
        catch err
            if isa(err,QueueComplete)
                println(err)
                println("Execution complete: ",err.value)
                break
            else
                println("Signal Queue Terminated for unknown reason")
                rethrow(err)
            end
        end
    end
end



# function run!(squeue::SignalQueue,signal_event::AbstractEvent)
#     task = evaluate_signal!(squeue,signal_event)
#     return task
# end

# function run!(executor::SimpleExecutor,squeue::SignalQueue,signal_event::AbstractSignalEvent)
#     #task = @schedule call!(squeue,signal_event)
#     task = evaluate_signal!(squeue,signal_event)
#     return task
# end

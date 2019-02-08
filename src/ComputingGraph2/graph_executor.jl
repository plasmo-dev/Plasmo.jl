###########################
#Serial executor just schedules tasks in the priority queue
###########################
#Signal Priorities
mutable struct SerialExecutor <: AbstractExecutor
    visits::Dict{AbstractComputeNode,Int}  #number of times each node has been computed
    final_time::Number
end
SerialExecutor() = SerialExecutor(Dict{AbstractDispatchNode,Int}(),200)
SerialExecutor(time) = SerialExecutor(Dict{AbstractDispatchNode,Int}(),time)

#This is the main execution method for an executor
execute!(graph::ComputingGraph,executor::AbstractExecutor) = execute!(graph.signalqueue,executor)
execute!(graph::ComputingGraph) = execute!(graph,SerialExecutor())

step(graph::ComputingGraph,executor::AbstractExecutor) = step(graph.signal_queue,executor)
step(graph::ComputingGraph) = step(graph.signal_queue)

function advance(graph::ComputingGraph,executor::AbstractExecutor,time::Number)
    @assert Float64(time) > 0 && now(graph) <= time
    while now(graph) <= Float64(time)
        step(graph,executor)
    end
end


# function run!(executor::SerialExecutor,queue::SignalQueue,signal_event::AbstractEvent)
#     task = run!(queue,signal_event)
#     #NOTE: Alternative execution mechanism task = @schedule call!(workflow,event)
#     return task
# end

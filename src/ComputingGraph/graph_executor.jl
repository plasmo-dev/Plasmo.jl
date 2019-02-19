###########################
#Serial executor just schedules tasks in the priority queue
###########################
#Signal Priorities
mutable struct SerialExecutor <: AbstractExecutor
    visits::Dict{AbstractComputeNode,Int}  #number of times each node has been computed
    final_time::Number
end
SerialExecutor() = SerialExecutor(Dict{AbstractComputeNode,Int}(),200)
SerialExecutor(time) = SerialExecutor(Dict{AbstractComputeNode,Int}(),time)

#This is the main execution method for an executor
execute!(graph::ComputingGraph,executor::AbstractExecutor) = execute!(graph.signalqueue,executor)
execute!(graph::ComputingGraph) = execute!(graph,SerialExecutor())

step(graph::ComputingGraph,executor::AbstractExecutor) = step(graph.signalqueue,executor)
step(graph::ComputingGraph) = step(graph.signalqueue)

debug_step(graph::ComputingGraph) = debug_step(graph.signalqueue)

run!(executor::SerialExecutor,squeue::SignalQueue,signal_event::SignalEvent) = evaluate_signal!(squeue,signal_event)

function advance(graph::ComputingGraph,executor::AbstractExecutor,time::Number)
    @assert Float64(time) > 0 && now(graph) <= time
    while now(graph) <= Float64(time)
        step(graph,executor)
    end
end

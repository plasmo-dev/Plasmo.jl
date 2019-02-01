# A Node Task
mutable struct NodeTask
    label::Symbol
    func::Function                   #the function to call
    args::Vector{Any}                #the function args
    kwargs::Dict{Any,Any}
    result::Union{Any,Nothing}       #the result after calling the event
    compute_time::Float64
    #schedule_delay::Float64
end
NodeTask() = NodeTask(Symbol("nodetask"*string(gensym())),() -> nothing,[],Dict(),nothing,0.0,0.0)
NodeTask(func::Function) =  NodeTask(Symbol("nodetask"*string(gensym())),func,[],Dict(),nothing,0.0,0.0)

NodeTask(label::Symbol,func::Function;args = [],kwargs = Dict(),compute_time = 0.0,schedule_delay = 0.0) = NodeTask(label,func,args,kwargs,nothing,compute_time,schedule_delay)


execute!(node_task::NodeTask) = node_task.result = node_task.func(node_task.args...,node_task.kwargs...)
getresult(node_task::NodeTask) = get(node_task.result)
getlabel(node_task::NodeTask) = node_task.label

getcomputetime(nodetask::NodeTask) = nodetask.compute_time

#NOTE: Getting rid of schedule delay
getscheduledelay(nodetask::NodeTask) = nodetask.schedule_delay
setcomputetime(nodetask::NodeTask,compute_time::Float64) = nodetask.compute_time = compute_time
setscheduledelay(nodetask::NodeTask,delay::Float64) = nodetask.schedule_delay = delay

function string(node_task::NodeTask)
    string(node_task.label)*"("*string(node_task.func)*")"
end
print(io::IO, node_task::NodeTask) = print(io, string(node_task))
show(io::IO, node_task::NodeTask) = print(io,node_task)

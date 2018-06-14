# A Node Task
mutable struct NodeTask
    label::Symbol
    func::Function                   #the function to call
    args::Vector{Any}                #the function args
    kwargs::Dict{Any,Any}
    result::Nullable{Any}            #the result after calling the event
    compute_time::Float64
    schedule_delay::Float64
end
NodeTask() = NodeTask(Symbol("nodetask"*string(gensym())),() -> nothing,[],Dict(),nothing,0.0,0.0)
NodeTask(func::Function) =  NodeTask(Symbol("nodetask"*string(gensym())),func,[],Dict(),nothing,0.0,0.0)
run!(node_task::NodeTask) = node_task.result = node_task.func(node_task.args...,node_task.kwargs...)
getresult(node_task::NodeTask) = get(node_task.result)

getcomputetime(nodetask::NodeTask) = nodetask.compute_time
getscheduledelay(nodetask::NodeTask) = nodetask.schedule_delay
setcomputetime(nodetask::NodeTask,compute_time::Float64) = nodetask.compute_time = compute_time
setscheduledelay(nodetask::NodeTask,delay::Float64) = nodetask.schedule_delay = delay

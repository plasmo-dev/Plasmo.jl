# A Node Task
mutable struct NodeTask
    node::Union{Nothing,AbstractComputeNode}                #A task has a pointer back to its node
    label::Symbol
    func::Function                   #the function to call
    args::Vector{Any}                #the function args
    kwargs::Dict{Any,Any}
    result::Union{Any,Nothing}       #the result after calling the event
    schedule_delay::Float64
    compute_time::Float64
    error_time::Float64
    finalize_time::Float64
end
#NodeTask() = NodeTask(Symbol("nodetask"*string(gensym())),() -> nothing,[],Dict(),nothing,0.0,0.0)
NodeTask(func::Function) =  NodeTask(nothing,Symbol("node_task"*string(gensym())),func,[],Dict(),nothing,0.0,mincomputetime(),0.0,0.0)
NodeTask(label::Symbol,func::Function;args = [],kwargs = Dict(),schedule_delay = 0.0,compute_time = 0.0,error_time = 0.0,finalize_time = 0.0) = NodeTask(nothing,label,func,args,kwargs,nothing,schedule_delay,compute_time,error_time,finalize_time)

execute!(node_task::NodeTask) = node_task.result = node_task.func(node_task.args...,node_task.kwargs...)
getresult(node_task::NodeTask) = node_task.result
getlabel(node_task::NodeTask) = node_task.label
getnode(node_task::NodeTask) = node_task.node

mincomputetime() = 1e-12
getcomputetime(nodetask::NodeTask) = nodetask.compute_time
geterrortime(nodetask::NodeTask) = nodetask.error_time
getfinalizetime(nodetask::NodeTask) = nodetask.finalize_time
setcomputetime(nodetask::NodeTask,compute_time::Float64) = nodetask.compute_time = compute_time

function string(node_task::NodeTask)
    string(node_task.label)*"("*string(node_task.func)*")"
end
print(io::IO, node_task::NodeTask) = print(io, string(node_task))
show(io::IO, node_task::NodeTask) = print(io,node_task)

##########################
#Node Task
##########################
# set_node_task(node::AbstractDispatchNode,func::Function) = node.node_task = DispatchFunction(func)
# set_node_task_arguments(node::AbstractDispatchNode,args::Vector{Any}) = node.node_task.args = args
# set_node_task_arguments(node::AbstractDispatchNode,arg::Any) = node.node_task.args = [arg]
# set_node_task_kwargs(node::AbstractDispatchNode,kwargs::Dict{Any,Any}) = node.node_task.kwargs = kwargs
# set_node_compute_time(node::AbstractDispatchNode,time::Float64) = node.compute_time = time

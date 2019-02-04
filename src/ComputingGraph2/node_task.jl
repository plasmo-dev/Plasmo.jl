struct TaskPriority
    priority::Int
    id::Int                 #each key should be unique
end

function isless(val1::TaskPriority,val2::TaskPriority) :: Bool
    if val1.priority < val2.priority
        return true
    elseif val1.priority == val2.priority && val1.id < val2.id
        return true
    else
        return false
    end
end

# A Node Task
mutable struct NodeTask
    node::DispatchNode
    label::Symbol
    func::Function                   #the function to call
    args::Vector{Any}                #the function args
    kwargs::Dict{Any,Any}
    result::Union{Any,Nothing}       #the result after calling the event
    compute_time::Float64
    #schedule_delay::Float64         #NOTE: Trying to find a better way to deal with task-specific data
end
#NodeTask() = NodeTask(Symbol("nodetask"*string(gensym())),() -> nothing,[],Dict(),nothing,0.0,0.0)
NodeTask(node::DispatchNode,func::Function) =  NodeTask(node,Symbol("nodetask"*string(gensym())),func,[],Dict(),nothing,0.0)#,0.0)
NodeTask(label::Symbol,func::Function;args = [],kwargs = Dict(),compute_time = 0.0,schedule_delay = 0.0) = NodeTask(label,func,args,kwargs,nothing,compute_time,schedule_delay)


execute!(node_task::NodeTask) = node_task.result = node_task.func(node_task.args...,node_task.kwargs...)
getresult(node_task::NodeTask) = node_task.result
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

##########################
#Node Task
##########################
# set_node_task(node::AbstractDispatchNode,func::Function) = node.node_task = DispatchFunction(func)
# set_node_task_arguments(node::AbstractDispatchNode,args::Vector{Any}) = node.node_task.args = args
# set_node_task_arguments(node::AbstractDispatchNode,arg::Any) = node.node_task.args = [arg]
# set_node_task_kwargs(node::AbstractDispatchNode,kwargs::Dict{Any,Any}) = node.node_task.kwargs = kwargs
# set_node_compute_time(node::AbstractDispatchNode,time::Float64) = node.compute_time = time

###########################
#Serial executor just schedules tasks in the priority queue
###########################
#Signal Priorities
mutable struct SerialExecutor <: AbstractExecutor
    visits::Dict{AbstractDispatchNode,Int}  #number of times each node has been computed
    final_time::Number
end
SerialExecutor() = SerialExecutor(Dict{AbstractDispatchNode,Int}(),200)
SerialExecutor(time) = SerialExecutor(Dict{AbstractDispatchNode,Int}(),time)

#This is the main execution method for an executor
function execute!(workflow::Workflow,executor::AbstractExecutor)  #this should be on the graph really
    # nodes = collectnodes(workflow)                           #get all the nodes
    # executor.visits = Dict(zip(nodes,zeros(length(nodes))))  #set up a map of each node to how many times it has been visited
    initialize(workflow)
    execute!(workflow.coordinator,executor,priority_map = workflow_priority_map)
end

execute!(workflow::Workflow) = execute!(workflow,SerialExecutor())

#run the next item in the schedule
#pop the next item off the queue and add it to Julia's scheduler to run it

step(workflow::Workflow,executor::AbstractExecutor) = step(workflow.coordinator,executor,priority_map = workflow_priority_map)
step(workflow::Workflow) = step(workflow.coordinator,priority_map = workflow_priority_map)
advance(workflow::Workflow,executor::AbstractExecutor) = advance(workflow.coordinator,executor,priority_map = workflow_priority_map)

# function advance(workflow::Workflow,executor::AbstractExecutor,time::Number)
#     while getcurrenttime(workflow) <= time
#         step()

function run!(executor::SerialExecutor,queue::SignalQueue,signal_event::AbstractEvent)#;priority_map = workflow_priority_map)
    #task = @schedule call!(workflow,event)
    task = run!(queue,signal_event)#,priority_map = priority_map)
    return task
end

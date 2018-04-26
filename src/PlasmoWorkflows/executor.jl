# function isless(a::EventKey, b::EventKey) :: Bool
#   (a.time < b.time) || (a.time == b.time && a.priority > b.priority) || (a.time == b.time && a.priority == b.priority && a.id < b.id)
# end

# schedule(node_event) => add to queue
# pop from queue => call!(workflow,node_event)
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
mutable struct SerialExecutor <: AbstractExecutor
    #max_visits_allowed::Int         #max visits on any dispatch node (not continuous nodes)
    visits::Dict{AbstractDispatchNode,Int}  #number of times each node has been computed
    final_time::Number
    #num_events_run::Int
end
SerialExecutor() = SerialExecutor(Dict{AbstractDispatchNode,Int}(),0)
SerialExecutor(time) = SerialExecutor(Dict{AbstractDispatchNode,Int}(),time)
#SerialExecutor(max_visits::Int) = SerialExecutor(max_visits,Dict{AbstractDispatchNode,Int}(),PriorityQueue{AbstractDispatchNode,DispatchPriorityValue}(),0)

#This is the main execution method for an executor
function execute!(workflow::Workflow,executor::AbstractExecutor)  #this should be on the graph really
    nodes = collectnodes(workflow)                               #get all the nodes
    executor.visits = Dict(zip(nodes,zeros(length(nodes))))  #set up a map of each node to how many times it has been visited
    #Setup priority queue of dispatch nodes
    #initialize_priority_queue(workflow)  #schedule dispatch and event functions
    # if executor.final_time != 0
    #     schedule(workflow,)

    while true
        try
            step(workflow,executor)             #step through the priority queue
            if workflow.time >= executor.final_time && workflow.time != 0
                throw(StopWorkflow())
            end
        catch err
            if isa(err,StopWorkflow)
                println("workflow execution complete")
                break
            else
                println("found error")
                rethrow(err)
            end
        end
    end
end

#run the next item in the schedule
#pop the next item off the queue and add it to Julia's scheduler to run it
function step(workflow::Workflow,executor::AbstractExecutor)
    isempty(workflow.queue) && throw("Queue is empty")
    #isempty(workflow.queue) && error("Queue is empty")
    #look at what's coming next
    (event, priority_key) = DataStructures.peek(workflow.queue)

    #Dequeue the event function
    DataStructures.dequeue!(workflow.queue)

    #Set the workflow time to the current event's time
    workflow.time = priority_key.time

    #for now, make this block until I figure out how to parallelize
    task =  run!(executor,workflow,event)  #Different dispatch calls do different things.  Might not want to pass the entire workflow
    #wait(task)  #maybe drop this
 end

function run!(executor::SerialExecutor,workflow::Workflow,event::AbstractEvent)
    #task = @schedule call!(workflow,event)
    task = call!(workflow,event)
    return task
end

#parallel executor uses @spawn to run the task

# ###########################
# #Parallel executor will spawn tasks.  Waiting should happen at node communication.
# ###########################
# mutable struct ParallelExecutor <: AbstractExecutor
#     max_visits_allowed::Int         #max visits on any dispatch node (not continuous nodes)
#     visits::Dict{AbstractDispatchNode,Int}  #number of times each node has been visited
#     queue::PriorityQueue{AbstractDispatchFunction,DispatchPriorityValue}
#     num_events_run::UInt
# end
# ParallelExecutor() = ParallelExecutor(100,Dict{AbstractDispatchNode,Int}(),PriorityQueue{AbstractDispatchNode,DispatchPriorityValue}(),0)
# ParallelExecutor(max_visits::Int) = ParallelExecutor(max_visits,Dict{AbstractDispatchNode,Int}(),PriorityQueue{AbstractDispatchNode,DispatchPriorityValue}(),0)
#
 # #advance the executor to the next time
 # function advance!(workflow::Workflow,executor::AbstractExecutor,delt::Float64)
 #
 #     # run currently scheduled nodes, these could trigger more nodes
 #     # dispatch_function, priority = DataStructures.peek(executor.queue)
 #     # if priority.time
 #     step(workflow,executor) #step through the priority queue
 #     #peek at the next item.  If it's a continuousNode, go to next time.
 # end

 #run the next item in the schedule
 # function step(workflow::Workflow,executor::ParallelExecutor)
 #      isempty(executor.queue) && error("Queue is empty")
 #      dispatch_function, priority = DataStructures.peek(executor.queue)
 #      DataStructures.dequeue!(executor.queue)
 #      @spawn call!(executor,dispatch_function)  #Different dispatch calls do different things
 #  end

 # function schedule(ev::AbstractEvent, delay::Number=zero(Float64); priority::Int8=zero(Int8), value::Any=nothing)
 #   state(ev) == processed && throw(EventProcessed(ev))
 #   env = environment(ev)
 #   bev = ev.bev
 #   bev.value = value
 #   env.heap[bev] = EventKey(now(env) + delay, priority, env.sid+=one(UInt))
 #   bev.state = scheduled
 #   ev
 # end


 #Assumes node preparation has been completed
 # function dispatch!(executor::SerialExecutor,node::DiscreteNode)
 #     task = @schedule run!(node) #schedule the node to run its function.  It also sets its result
 #     executor.visits[node] += 1
 #     node.status = :complete
 #     return task
 # end

 # #run the next node on the event queue
 # function step!(executor::AbstractExecutor)
 #     dequeue!(executor.queue)
 # end

#nodes_ready = [node for node in nodes if is_ready(node)]  #a node is ready if it has values in all of its input channels and has an active status
# if isempty(nodes_ready)
#     println("all nodes completed")
#     break
# end


        #dispatch the current ready nodes  (Do this through an asyncmap?)
        # for node in nodes_ready
        #     prepare!(node)  #set node arguments
        #     cond = dispatch!(executor,node)
        #     wait(cond)          #wait for the result?
        #     println(cond)
        #     set_complete(node)
        #
        #     #set output to current result
        #     set_output_to_result(node)  #set the node's output to its latest result
        #
        #     #update neighbor inputs through edges
        #     #NOTE: Possibly run the delay task here?
        #     for edge in out_edges(workflow,node)
        #         neighbor = getconnectedto(workflow,edge)
        #         neighbor.input.data[edge] = node.output.data[edge]
        #         #if condition_check
        #         #    set_ready(neighbor)
        #         #end
        #         set_ready(neighbor)
        #     end
        # end

#####################
# Parallel Executor
#####################

# mutable struct ParallelExecutor <: AbstractExecutor
#     max_visits_allowed::Int
#     visits::Dict{WorkflowNode,Int}  #number of times each node has been visited
# end
# ParallelExecutor() = ParallelExecutor(100,Dict{WorkflowNode,Int}())
# ParallelExecutor(max_visits::Int) = ParallelExecutor(max_visits,Dict{WorkflowNode,Int}())
#
# function dispatch!(executor::ParallelExecutor,node::WorkflowNode)
#     future = @spawn run!(node)
#     executor.visits[node] += 1
#     node.status = :complete
#     return future
# end

#Task test: Running an execution loop

#Assume we have a list of nodes with inputs ready

#Schedule these nodes to run

#When we dispatch these nodes, run a callback that triggers their neighbors.  When neighbors get triggered, we check whether they pass their condition (prepare) functions.
#If yes, the neighbors get scheduled as well.  We update the visit count for the visited neighbor.

mutable struct Input
    data::Vector{Any}  #input for each edge coming in
end
Input() = Input(Vector{Any}())

mutable struct Output
    data::Vector{Any}  #output for each edge going out
end
Output() = Output(Vector{Any}())

mutable struct Result
    result::Any
end
Result() = Result(Nullable())


const WorkFlowStatus = (:idle,:ready,:complete)  #might use these as node statuses

mutable struct WorkflowNode
    label::Symbol
    input::Input       #input data
    output::Output     #output data
    status::Symbol     #possibilities include: ready, complete, error
    prepare::Function  #function to clean inputs to pass into func.  Could also be used as a condition check.  If no prepare, the input just goes into the args.
    func::Function     #the actual function to call
    args               #the current arguments.  run the function with these arguments
    kwargs             #the current keyword arguments.  also pass these to the function
    result             #The result of running the function
end
WorkflowNode() = WorkflowNode(Symbol("node"),Input(),Output(),:idle,() -> nothing,() -> nothing,(),Dict(),Result())

#Workflow node functions
set_function(node::WorkflowNode,func::Function) = node.func = func
set_prepare_function(node::WorkflowNode,func::Function) = node.prepare = func
set_arguments(node::WorkflowNode,args) = node.args = args
set_ready(node::WorkflowNode) = node.status = :ready
is_ready(node::WorkflowNode) = node.status == :ready
set_finished(node::WorkflowNode) = node.status = :done
set_input_data(node::WorkflowNode,data) = node.input.data = data

#is_ready() = node.condition_check()

#run the prepare function on a node.  This will determine whether the node should be schedule or not
function prepare!(node::WorkflowNode)
    result = node.prepare(node)   #By default, a prepare function converts the node Input into arguments
    return result
end

function run!(node::WorkflowNode)
    result = node.func(node.args...)
    node.result.result = result
    return result
end

mutable struct Executor
    nodes::Vector{WorkflowNode}     #The nodes in the executor context.  This will be a graph eventually
    visits::Dict{WorkflowNode,Int}  #number of times each node has been visited
    max_visits_allowed::Int
end
Executor() = Executor(Vector{WorkflowNode}(),Dict{WorkflowNode,Int}(),100)
Executor(nodes::Vector{WorkflowNode}) = Executor(nodes,Dict(zip(nodes,zeros(length(nodes)))),100)

function dispatch!(executor::Executor,node::WorkflowNode)
    if prepare!(node) == true       #maybe call this isready(node)?
        task = @schedule run!(node) #schedule the node to run its function.  Use spawn for a parallel executor
        executor.visits[node] += 1
        node.status = :done
        return task
    end
end

#Do some graph traversal with our executor
#This is the main execution method for an executor
function execute!(executor::Executor)  #this should be on the graph really
    #nodes are ready if they have arguments.  Figure out logic to determine if a node is ready
    #nodes_ready = ?
    nodes_ready = [node for node in executor.nodes if is_ready(node)]  #we'll just assume the first node is ready for now
    while true

        if isempty(nodes_ready)
            break
        end
        if any(collect(values(executor.visits)) >= executor.max_visits)
            break
        end

        #Do this through an asyncmap?
        for node in nodes_ready
            cond = dispatch!(executor,node)
            wait(cond) #wait for the result
            node.output = node.result  #set the node's output to its latest result
        end

        #update nodes_ready based on results

    end
end

#################################################################
# Try using these objects in a simple back and forth scenario
#################################################################
function simple_task(i)
    return 2*i
end

function prepare_node(node::WorkflowNode)
    node.args = node.input.data[1]
    return true
end

function dispatch!(node::WorkflowNode)
    if prepare!(node) == true       #maybe call this isready(node)?
        task = @schedule run!(node) #schedule the node to run its function.  Use spawn for a parallel executor
        node.status = :done
        return task
    end
end


node1 = WorkflowNode()
set_function(node1,simple_task)
#set_arguments(node1,1)
set_input_data(node1,[1])
set_prepare_function(node1,prepare_node)
set_ready(node1)

node2 = WorkflowNode()
set_function(node2,simple_task)  #don't set argument
set_prepare_function(node2,prepare_node)

#won't use this for this run
executor = Executor([node1,node2])

#execute!(executor)


nodes = [node1,node2]
#run a test execution with just 2 nodes

visits = Dict(zip(nodes,zeros(length(nodes))))
max_visits = 10

#Don't need the @async here.  It just starts up a local task and runs through the loop without waiting
#@async begin
while true
    nodes_ready = [node for node in nodes if is_ready(node)]
    other_nodes = [node for node in nodes if !is_ready(node)]

    if isempty(nodes_ready)
        println("all nodes completed")
        break
    end
    if any(collect(values(visits)) .>= max_visits)
        println("reached maximum number of visits")
        break
    end

    for node in nodes_ready
        cond = dispatch!(node)
        println(cond)  #this is a task
        if isa(cond,Task)
            wait(cond)                  #wait for the result
            node.output.data = [node.result.result]   #set the node's output to its latest result
            set_finished(node)
            visits[node] += 1
            #set the input of other nodes
            for other_node in other_nodes
                other_node.input.data = node.output.data
            end
        end
    end
    map(set_ready,other_nodes)
end
#end



#execute(executor)



# info(logger, "Node $id ($desc): running.")
# cond = dispatch!(exec, node)
# debug(logger, "Waiting on $cond")
# wait(cond)
# info(logger, "Node $id ($desc): complete.")

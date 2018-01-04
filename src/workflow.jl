import LightGraphs:AbstractGraph,Graph,DiGraph,add_vertex!,add_edge!,nv,ne,vertices,edges,in_neighbors,out_neighbors,in_edges,out_edges,src,dst,degree

using Plasmo
import Plasmo:AbstractPlasmoGraph,AbstractNode,AbstractEdge,add_node!

#Workflow Graph
type Workflow <: Plasmo.AbstractPlasmoGraph
    graph::AbstractGraph                        #a lightgraph
    nodes::Dict{Int,AbstractNode}               #includes nodes in the subgraphs as well
    edges::Dict{LightGraphs.Edge,AbstractEdge}              #includes edges in the subgraphs as well
end

Workflow() =  Workflow(DiGraph(),Dict{Int,AbstractNode}(),Dict{LightGraphs.Edge,AbstractEdge}())


#data in or out of executed nodes.  maps to edges in and out of nodes
mutable struct DataInOut
    data::Dict{AbstractEdge,Any}
end
DataInOut() = DataInOut(Dict{AbstractEdge,Any}())
#Make convenient Input and Output structs
const Input = DataInOut
const Output = DataInOut

#This might end up as anything
mutable struct Result
    result::Any #A Future or Task?
end
Result() = Result(Nullable())
#getresult(res::Result) = res.result

#Workflow Node
mutable struct WorkflowNode <: AbstractNode  #A Dispatch node
    index::Dict{Workflow,Int}                #map to an index in each workflow containing the node
    label::Symbol
    attributes::Dict{Any,Any}                #A model is an attribute, could be other data, etc...
    input::Input       #node input data
    output::Output     #node output data
    status::Symbol     #possibilities include: idle, ready, complete, error
    prepare::Function  #function to clean inputs to pass into func.  Can also be used as a condition check.  If no prepare, the input just goes into the args.
    func::Function     #the actual function to call
    args               #run the function with these arguments
    kwargs             #also get keyword arguments
    result::Result             #::DeferredFuture #need to figure out how these work
end

getinputdata(node::WorkflowNode) = node.input.data
getoutputdata(node::WorkflowNode) = node.output.data

#by default, prepare by setting args to the latest input
function default_prepare!(node::WorkflowNode)
    node.args = collect(values(getinputdata(node)))  #this will be all of the dictionary values
end

# Node constructors
#WorkflowNode() = WorkflowNode(Dict{WorkflowGraph,Int}(), Symbol("node"),Dict{Any,Any}(),Model(),NodeLinkData(),DeferredFuture())
WorkflowNode() = WorkflowNode(Dict{Workflow,Int}(), Symbol("node"),Dict{Any,Any}(),Input(),Output(),:idle,default_prepare!,() -> nothing,(),Dict(),Result())
create_node() = WorkflowNode()

function WorkflowNode(workflow::Workflow)
    add_vertex!(workflow.graph)
    i = nv(workflow.graph)
    label = Symbol("node"*string(i))
    node = WorkflowNode(Dict(workflow => i),label,Dict{Any,Any}(),Input(),Output(),:idle,default_prepare!,() -> nothing,(),Dict(),Result())
    workflow.nodes[i] = node
    return node
end

add_node!(workflow::Workflow) = WorkflowNode(workflow)
add_vertex!(workflow::Workflow) = WorkflowNode(workflow)
add_vertex!(workflow::Workflow,node::WorkflowNode) = add_node!(workflow,node)

#Workflow node functions
set_function(node::WorkflowNode,func::Function) = node.func = func
set_prepare_function(node::WorkflowNode,func::Function) = node.prepare = func
set_arguments(node::WorkflowNode,args) = node.args = args
#Node status functions
set_ready(node::WorkflowNode) = node.status = :ready
is_ready(node::WorkflowNode) = node.status == :ready
set_complete(node::WorkflowNode) = node.status = :complete

getresult(node::WorkflowNode) = node.result.result


#Set all edge input data to the given data
set_input_data(workflow::Workflow,node::WorkflowNode,data) = node.input.data = Dict(zip(in_edges(workflow,node),[data for i = 1:in_degree(workflow,node)]))


set_output_to_result(node::WorkflowNode) = node.output.data =  Dict(zip(out_edges(workflow,node),[getresult(node) for i = 1:in_degree(workflow,node)]))


#run the prepare function on a node.  This will determine whether the node should be scheduled or not
function prepare!(node::WorkflowNode)
    node.prepare(node)   #By default, a prepare function converts the node Input into arguments
end

function run!(node::WorkflowNode)
    result = node.func(node.args...)
    node.result.result = result
    return node
end


##########################
# Communication Edges
#########################
mutable struct CommunicationEdge <: AbstractEdge
    index::Dict{AbstractPlasmoGraph,LightGraphs.Edge}
    label::Symbol
    delay::Number  #delay transfer of information  #use a sleep?
end

#Fall back to base methods for adding edges



##########################
# Executors
##########################
abstract type AbstractExecutor end

#Async executor just schedules tasks repeatedly
mutable struct AsyncExecutor <: AbstractExecutor
    #workflow::Workflow    #The nodes in the executor context.  This will be a graph eventually
    max_visits_allowed::Int
    visits::Dict{WorkflowNode,Int}  #number of times each node has been visited
    #events::Vector{Event}
end
AsyncExecutor() = AsyncExecutor(100,Dict{WorkflowNode,Int}())
AsyncExecutor(max_visits::Int) = AsyncExecutor(max_visits,Dict{WorkflowNode,Int}())
#Executor(nodes::Vector{WorkflowNode}) = Executor(nodes,Dict(zip(nodes,zeros(length(nodes)))),100)

#Assumes node preparation has been completed
function dispatch!(executor::AsyncExecutor,node::WorkflowNode)
    task = @schedule run!(node) #schedule the node to run its function.  Use spawn for a parallel executor
    executor.visits[node] += 1
    node.status = :complete
    return task
end


mutable struct ParallelExecutor <: AbstractExecutor
    #workflow::Workflow    #The nodes in the executor context.  This will be a graph eventually
    max_visits_allowed::Int
    visits::Dict{WorkflowNode,Int}  #number of times each node has been visited
    #events::Vector{Event}
end
ParallelExecutor() = ParallelExecutor(100,Dict{WorkflowNode,Int}())
ParallelExecutor(max_visits::Int) = ParallelExecutor(max_visits,Dict{WorkflowNode,Int}())

function dispatch!(executor::ParallelExecutor,node::WorkflowNode)
    future = @spawn run!(node)
    executor.visits[node] += 1
    node.status = :complete
    return future
end

#Do some graph traversal with our executor
#This is the main execution method for an executor
function execute!(workflow::Workflow,executor::AbstractExecutor)  #this should be on the graph really
    nodes = collect(values(workflow.nodes))
    executor.visits = Dict(zip(nodes,zeros(length(nodes))))
    #Primary execution task
    while true
        nodes_ready = [node for node in nodes if is_ready(node)]
        if isempty(nodes_ready)
            println("all nodes completed")
            break
        end
        if any(collect(values(executor.visits)) .>= executor.max_visits_allowed)
            println("reached maximum number of visits")
            break
        end

        #dispatch the current ready nodes  (Do this through an asyncmap?)
        for node in nodes_ready
            prepare!(node)  #set node arguments
            cond = dispatch!(executor,node)
            wait(cond)          #wait for the result?
            println(cond)
            set_complete(node)

            #set output to current result
            set_output_to_result(node)  #set the node's output to its latest result

            #update neighbor inputs through edges
            #NOTE: Possibly run the delay task here?
            for edge in out_edges(workflow,node)
                neighbor = getconnectedto(workflow,edge)
                neighbor.input.data[edge] = node.output.data[edge]
                #if condition_check
                #    set_ready(neighbor)
                #end
                set_ready(neighbor)
            end
        end
    end
end







# #@async begin
# while true
#     nodes_ready = [node for node in nodes if is_ready(node)]
#     other_nodes = [node for node in nodes if !is_ready(node)]
#
#     if isempty(nodes_ready)
#         println("all nodes completed")
#         break
#     end
#     if any(collect(values(visits)) .>= max_visits)
#         println("reached maximum number of visits")
#         break
#     end
#
#     for node in nodes_ready
#         cond = dispatch!(node)
#         println(cond)  #this is a task
#         if isa(cond,Task)
#             wait(cond)                  #wait for the result
#             node.output.data = [node.result.result]   #set the node's output to its latest result
#             set_finished(node)
#             visits[node] += 1
#             #set the input of other nodes
#             for other_node in other_nodes
#                 other_node.input.data = node.output.data
#             end
#         end
#     end
#     map(set_ready,other_nodes)
# end


####################################
#Input and Output Structs
####################################
# type Output
#     node::WorkflowNode  #workflow node this output refers to
#     edges::Vector{CommunicationEdge}  #outgoing communications
# end
#
# type Input
#     node::WorkflowNode
#     edges::Vector{CommunicationEdge}  #incoming communications
# end

#const Input = Output  #These are technically the same thing?

#Executors
#look at dispatcher.jl to figure out a way to do this.  It needs to know to loop around when tasks get reset to their ready state.
# abstract type AbstractExecutor end
#
# type SerialExecutor <: AbstractExecutor
#     max_visits::Integer
#     starting_node::WorkflowNode
# end
#
# type AsyncExecutor <: AbstractExecutor
# end
#
# function execute(exec::AbstractExecutor,workflow::Workflow)
# end
#
# function set_starting_node(executor::AbstractExecutor,node::WorkflowNode)
# end

# #not sure what to do with this yet...
# type TaskCondition
# end

#A task has access to attributes on its virtual node including Input and Output
# type WorkflowTask
#     #task::Task
#     status  #corresponds to a julia task status
#     conditions::Vector{Function}  #Functions which must evaluate to true or false
#     func::Function
#     input   #input from the virtual node's input channel?
# end

#has a mapping for each edge into the workflow node
# type Input
#     vals
# end


# mutable struct Input
#     data::Vector{Any}  #input for each edge coming in
# end
# Input() = Input(Vector{Any}())
#
# mutable struct Output
#     data::Vector{Any}  #output for each edge going out
# end
# Output() = Output(Vector{Any}())

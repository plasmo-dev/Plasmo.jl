using LightGraphs

#Workflow Graph
type Workflow
    graph::AbstractGraph  #a lightgraph
    nodes::Dict{Int,AbstractNode}               #Includes nodes in the subgraphs as well
    edges::Dict{LightGraphs.Edge,AbstractEdge}  #Includes edges in the subgraphs as well
end

Workflow() =  Workflow(DiGraph(),Dict{Int,AbstractNode}(),Dict{LightGraphs.Edge,AbstractEdge}())

#Workflow Node
type WorkflowNode <: AbstractNode  #A Dispatch node
    index::Dict{PlasmoGraph,Int} #map to an index in each graph containing the node
    label::Symbol
    attributes::Dict{Any,Any}  #A model is an attribute
    input::Input       #input channel
    output::Output     #output channel
    status::Symbol     #possibilities include: ready, complete, error
    func::Function
    args::Vector       #run the function with these arguments
    prepare::Function  #function to clean inputs to pass into func.  Could also be used as a condition check.  If no prepare, the input just goes into the args.
end

# Node constructors
WorkflowNode() = WorkflowNode(Dict{WorkflowoGraph,Int}(), Symbol("node"),Dict{Any,Any}(),Model(),NodeLinkData())
function PlasmoNode(g::PlasmoGraph)
    add_vertex!(g.graph)
    i = nv(g.graph)
    label = Symbol("node"*string(i))
    node = PlasmoNode(Dict(g => i),label,Dict(),Model(),NodeLinkData())
    g.nodes[i] = node
    return node
end

#Add an existing node to a graph.  It's possible to pass a user specified index.  This is useful for copying graphs
function add_node!(g::AbstractPlasmoGraph,node::AbstractNode;index = nv(g.graph)+1)
    add_vertex!(g.graph)
    #i = nv(g.graph)
    node.index[g] = index #sets a dictionary reference
    g.nodes[index] = node #sets the graph reference to the node
    return node
end
create_node() = PlasmoNode()
add_node!(g::PlasmoGraph) = PlasmoNode(g)
add_vertex!(g::PlasmoGraph) = PlasmoNode(g)
add_vertex!(g::PlasmoGraph,node::PlasmoNode) = add_node!(g,node)
#add a node to the workflow
function add_node(workflow::Workflow)
end


type CommunicationEdge <: AbstractEdge
    delay::Number
end

function add_edge(workflow::Workflow,n1::WorkflowNode,n2::WorkflowNode)
end


type Output
    node::WorkflowNode
    edges::Vector{CommunicationEdge}
end

type Input
    node::WorkflowNode
    edges::Vector{CommunicationEdge}
end

const Input = Output  #These are technically the same thing?

#Executors
#look at dispatcher.jl to figure out a way to do this.  It needs to know to loop around when tasks get reset to their ready state.
abstract type AbstractExecutor end

type SerialExecutor <: AbstractExecutor
    max_visits::Integer
    starting_node::WorkflowNode
end

type AsyncExecutor <: AbstractExecutor
end

function execute(exec::AbstractExecutor,workflow::Workflow)
end

function set_starting_node(executor::AbstractExecutor,node::WorkflowNode)
end

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

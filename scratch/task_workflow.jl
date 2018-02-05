include("../src/workflow.jl")

#using Plasmo

function simple_task(i)
    return 2*i
end

workflow = Workflow()

node1 = add_node(workflow)
set_function(node1,simple_task)

#set_arguments(node1,1)
#set_prepare_function(node1,prepare_node)

node2 = add_node(workflow)
set_function(node2,simple_task)  #don't set argument
#set_prepare_function(node2,prepare_node)

#add communication between nodes
e1 = add_edge(workflow,node1,node2)
e2 = add_edge(workflow,node2,node1)

#set input data after constructing the workflow
set_input_data(workflow,node1,1)
set_ready(node1)

executor = AsyncExecutor(10)
#executor = ParallelExecutor(10)

execute!(workflow,executor)

println(getresult(node1))
println(getresult(node2))

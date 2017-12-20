function simple_task(i)
    i = i + 1
    println(i)
    return i
end

workflow = Workflow() #a workflow graph

n1 = add_node(workflow,simple_task)  #default tasks or require something?
set_arguments(n1,1)  #set the initial argument to pass to this task's function

n2 = add_node(workflow)
set_task(n2,simple_task)
add_edge(workflow,n1,n2)  #communication link

n3 = add_node(workflow,simple_task)
add_edge(workflow,n2,n3)
add_edge(workflow,n3,n1)

executor = SerialExecutor()
# execute(executor,workflow) #error, no starting node

set_starting_node(executor,n1)  #tell the workflow where to start if there are dependencies
set_max_visits(executor,500)    #stop if the same node is visited 500 times

execute(executor,workflow)

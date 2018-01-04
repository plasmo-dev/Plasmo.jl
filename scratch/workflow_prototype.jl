function simple_task(i)
    i = i + 1
    println(i)
    return i
end

workflow = Workflow() #a workflow graph (dispatch graph) DiGraph()

n1 = add_node(workflow,simple_task)  #default tasks or require something?
#n1 = add_node(workflow,simple_task,1)
set_arguments(n1,1)  #set the initial argument to pass to this task's function

n2 = add_node(workflow)
set_task(n2,simple_task) #no arguments
add_edge(workflow,n1,n2)  #create a communication link (could be a channel?)

#n3 = add_node(workflow,simple_task)
#add_edge(workflow,n2,n3)
add_edge(workflow,n2,n1)  #create a communication link back to n1

executor = AsyncExecutor()  #uses @schedule to run tasks
# executor = ParallelExecutor() #uses @spawn to run tasks
# executor = SerialExecutor()  Might be easier to just call Async with a single process
# execute(executor,workflow) #error, could not find a starting node

set_starting_node(workflow,n1)  #tell the workflow where to start if there are dependencies
set_max_visits(executor,500)    #stop if the same node is visited 500 times

execute(executor,workflow)

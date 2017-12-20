function solve_master(master::WorkflowNode,m::Model)
    inputs = get_input(master)
    add_cuts(m,inputs)  #each input is a subgradient
    solve(m)
end

function solve_subproblem(m::Model)
    solve(m)
end

#use subgradients to add cuts to master problem
function add_cuts(m::Model,subgradients)
end

function prepare_master(master::WorkflowNode,m::Model,async_param::Number)
    inputs = get_input(master)  #get the current inputs from each edge
    n_neighbors = get_n_neighbors(master)
    return length(inputs)/n_neighbors >= async_param
    # if length(inputs)/n_neighbors >= async_param #enough subproblems have finished
    #     add_cuts(m,inputs)  #each input is a subgradient
    #     set_status(master,:ready)
    # end
end

workflow = Workflow()

master_task = add_node(workflow)
set_task(master_task,solve_master)
set_condition(master_task,prepare_master)

sub_tasks = []
for i = 1:10
    sub_task = add_node(workflow)
    set_task(sub_task,solve_subproblem)
    add_edge(master_task,sub_task) #communicate first stage information to sub tasks
    add_edge(sub_task,master_task) #communicate subgradients to master
end

executor = SerialExecutor()   #Serial Executor just schedules nodes in serial.  Might use graph traversal for this
set_starting_node(executor,master_task)
set_max_visits(executor,1000)

execute(executor,workflow)

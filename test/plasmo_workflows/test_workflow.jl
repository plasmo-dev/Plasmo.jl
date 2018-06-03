include("../../src/PlasmoWorkflows2/PlasmoWorkflows.jl")
using PlasmoWorkflows

# using PlasmoWorkflows

function simple_func1(x::String)
    println(x)
    return 5
end

function simple_func2(workflow::Workflow,node::DispatchNode)
    println("Running simple_func2 at t = $(getcurrenttime(workflow))")
    println(node[:x])
    return true
end

#Create the workflow
workflow = Workflow()

#Add the first workflow node
w1 = add_dispatch_node!(workflow)
set_node_task(w1,simple_func1)
set_node_task_arguments(w1,"hello from $w1")
set_node_compute_time(w1,1.0)               #node will take 1 unit of time to complete
#
# #Add the second workflow node
w2 = add_dispatch_node!(workflow)
set_node_task(w2,simple_func2)
set_node_task_arguments(w2,[workflow,w2])
addattribute!(w2,:x)
#
channel1 = connect!(workflow,w1[:result],w2[:x],comm_delay = 1)
getdelay(channel1)

setinitialsignal(w1,Signal(:execute))

#initialize(workflow)

# step(workflow)
# step(workflow)
# step(workflow)
# step(workflow)
# step(workflow)
# step(workflow)
# step(workflow)
# step(workflow)
# step(workflow)

execute!(workflow)

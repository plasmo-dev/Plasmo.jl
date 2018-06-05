#include("../../src/PlasmoWorkflows/PlasmoWorkflows.jl")
using Plasmo.PlasmoWorkflows

function simple_func1(workflow::Workflow,x::String)
    println("Running simple_func1 at t = $(getcurrenttime(workflow))")
    println(x)
    return 5
end

function simple_func2(workflow::Workflow,node::DispatchNode)
    println("Running simple_func2 at t = $(getcurrenttime(workflow))")
    return true
end

#Create the workflow
workflow = Workflow()

#Add the first workflow node
w1 = add_dispatch_node!(workflow,continuous = true)
set_node_task(w1,simple_func1)
set_node_task_arguments(w1,[workflow,"hello from node 1"])
set_node_compute_time(w1,1.0)  #node will take 1 unit of time to complete the task

#Add the second workflow node
w2 = add_dispatch_node!(workflow)
set_node_task(w2,simple_func2)
set_node_task_arguments(w2,[workflow,w2])
addattribute!(w2,:x)

#Connect result from w1 to attribute x in w2.  It takes 0.5 unit(s) of time to communicate.
channel1 = connect!(workflow,w1[:result],w2[:x],comm_delay = 2)

setinitialsignal(w1,Signal(:execute))

execute!(workflow)

true

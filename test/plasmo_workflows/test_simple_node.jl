#include("../../src/PlasmoWorkflows/PlasmoWorkflows.jl")
using Plasmo.PlasmoWorkflows

function simple_func1(x::String)
    println("Running simple_func1 with string: $x")
    return 5
end

function simple_func2(workflow::Workflow,node::DispatchNode)
    println("Running simple_func2 at t = $(getcurrenttime(workflow))")
    return true
end

#Create the workflow
workflow = Workflow()

#Add the first workflow node
w1 = add_dispatch_node!(workflow,continuous = false)
set_node_task(w1,simple_func1)
set_node_task_arguments(w1,"hello from $w1")
set_node_compute_time(w1,1.0)  #node will take 1 unit of time to complete the task
#

#Add the second workflow node
w2 = add_dispatch_node!(workflow)
set_node_task(w2,simple_func2)
set_node_task_arguments(w2,[workflow,w2])
addattribute!(w2,:x)

#Connect result from w1 to attribute x in w2.  It takes 1 unit of time to communicate.
channel1 = connect!(workflow,w1[:result],w2[:x],comm_delay = 1)
#getdelay(channel1)

setinitialsignal(w1,Signal(:execute))

schedulesignal(workflow,DataSignal(:update_attribute,w2[:x],10),w2,6)

#TEST STEP BY STEP
# initialize(workflow)
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

@assert getglobalvalue(w1[:result]) == 5
@assert getglobalvalue(w2[:x]) == 10

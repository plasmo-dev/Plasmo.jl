using Plasmo

#Create some simple tasks
function simple_func1(x::String)
    println("Running simple_func1 with string: $x")
    return 5
end

function simple_func2(graph::ComputingGraph,node::ComputeNode)
    println("Running simple_func2 at t = $(now(graph))")
    return "test"
end

#Create the workflow
graph = ComputingGraph()

#Add the first workflow node
n1 = addnode!(graph)
task1 = addnodetask!(graph,n1,:task1,simple_func1,args = ["hello from $n1"],compute_time = 1.0)
#
#
# #Add the second workflow node
# w2 = add_dispatch_node!(workflow)
# node_task = addnodetask!(workflow,w2,:run_w2,simple_func2,args = [workflow,w2])
# addworkflowattribute!(w2,:x)
# addtrigger!(w2,node_task,w2[:x])
#
# #Connect result from w1 to attribute x in w2.  It takes 1 unit of time to communicate.
# result = getnoderesult(w1,:run_w1)
# channel1 = connect!(workflow,result,w2[:x],comm_delay = 1)
#
# schedulesignal(workflow,Signal(:execute,task1),w1,0)
# schedulesignal(workflow,DataSignal(:update_attribute,w2[:x],10),w2,6)

#TEST STEP BY STEP
# step(workflow)
# step(workflow)
# step(workflow)
# step(workflow)
# step(workflow)
# step(workflow)
# step(workflow)
# step(workflow)
# step(workflow)

# execute!(workflow)
#
# @assert getglobalvalue(result) == 5
# @assert getglobalvalue(w2[:x]) == 10

true

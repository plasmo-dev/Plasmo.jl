using Plasmo

#Create some simple tasks
function simple_func1(x::String)
    println("Running simple_func1 with string: $x")
    return 5
end

function simple_func2(graph::ComputingGraph,node::ComputeNode)
    println("Running simple_func2 at t = $(now(graph))")
    #setvalue(node[:x],10)
    node[:x] = 10
    return "test"
end

#Create the graph
graph = ComputingGraph()

#Add the first graph node
n1 = addnode!(graph)
task1 = addnodetask!(graph,n1,:task1,simple_func1,args = ["hello from $n1"],compute_time = 1.0)

#Add the second compute node
n2 = addnode!(graph)
task2 = addnodetask!(graph,n2,:task2,simple_func2,args = [graph,n2])
x = addcomputeattribute!(n2,:x)
addtasktrigger!(graph,n2,task2,signal_received(n2[:x]))

# #Connect result from w1 to attribute x in w2.  It takes 1 unit of time to communicate.
result_attribute = getnoderesult(n1,task1)
edge1 = connect!(graph,result_attribute,n2[:x],delay = 1,send_on = signal_updated(result_attribute))

queuesignal!(graph,signal_execute(task1),n1,0)
#schedulesignal(graph,DataSignal(:update_attribute,w2[:x],10),w2,6)

#TEST STEP BY STEP
# step(graph)
# getqueue(graph)
# step(graph)
# step(graph)
# step(graph)
# step(graph)
# step(graph)
# step(graph)
# step(graph)
# step(graph)

execute!(graph)
#
@assert getglobalvalue(result_attribute) == 5
@assert getglobalvalue(n2[:x]) == 10

true

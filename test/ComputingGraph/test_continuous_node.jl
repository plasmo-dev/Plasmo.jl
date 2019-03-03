using Plasmo

function simple_func1(graph::ComputingGraph,count::NodeAttribute,s::String)
    println("Running simple_func1 at t = $(now(graph))")
    println(s)
    Plasmo.PlasmoComputingGraph.setvalue(count,getlocalvalue(count) + 1)
    return getlocalvalue(count)
end

function simple_func2(graph::ComputingGraph,node::ComputeNode)
    println("Running simple_func2 at t = $(now(graph))")
    return true
end

#Create the workflow
graph = ComputingGraph()

#Add the first workflow node
n1 = addnode!(graph)
#x = addcomputeattribute!(n1,:x,0)
count = addcomputeattribute!(n1,:count,0)
task1 = addnodetask!(graph,n1,:run_n1,simple_func1,args = [graph,count,"hello from $n1"],compute_time = 1.0,triggered_by = signal_updated(count))

#addtasktrigger!(graph,n1,task1,Finalized(task1))

#Add the second workflow node
n2 = addnode!(graph)
task2 = addnodetask!(graph,n2,:run_n2,simple_func2,args = [graph,n2])
addcomputeattribute!(n2,:x)
addtasktrigger!(graph,n2,task2,signal_received(n2[:x]))

#Connect result from w1 to attribute x in w2.  It takes 0.5 unit(s) of time to communicate.
result = getnoderesult(n1,task1)
edge1 = connect!(graph,result,n2[:x],delay = 2,send_on = signal_updated(result))

queuesignal!(graph,signal_execute(task1),n1,0)

execute!(graph)

true

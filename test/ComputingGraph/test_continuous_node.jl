using Plasmo

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
w1 = add_dispatch_node!(workflow)
task1 = addnodetask!(workflow,w1,:run_w1,simple_func1,args = [workflow,"hello from $w1"],compute_time = 1.0,continuous = true)

#Add the second workflow node
w2 = add_dispatch_node!(workflow)
node_task = addnodetask!(workflow,w2,:run_w2,simple_func2,args = [workflow,w2])
addworkflowattribute!(w2,:x)
addtrigger!(w2,node_task,w2[:x])

#Connect result from w1 to attribute x in w2.  It takes 0.5 unit(s) of time to communicate.
result = getnoderesult(w1,:run_w1)
channel1 = connect!(workflow,result,w2[:x],comm_delay = 2)

schedulesignal(workflow,Signal(:execute,task1),w1,0)

execute!(workflow)

true

using PlasmoWorkflows
using PlasmoGraphBase

function simple_func1(x::String)
    println(x)
    return x
end

function simple_func2(workflow::Workflow,node::DispatchNode)
    println("Running simple_func2 @ t = $(getcurrenttime(workflow))")
    println("Current input = $(getchanneldata_in(node,1))")
    return true
end

#Create the workflow
workflow = Workflow()

#Add the first workflow node
w1 = add_node!(workflow)
set_node_function(w1,simple_func1)
set_node_function_arguments(w1,"hello")
set_node_compute_time(w1,1.0)               #node will take 1 unit of time to complete

# #Add the second workflow node
w2 = add_node!(workflow)
set_node_function(w2,simple_func2)
set_node_function_arguments(w2,[workflow,w2])
#
# #Connect with default channels.
e1 = connect!(workflow,w1,w2)

getdelay(e1)

@assert getconnectedto(workflow,e1) == w2
@assert getconnectedfrom(workflow,e1) == w1

getnumchannels(w1.output)
getnumchannels(w2.input)


trigger!(workflow,w1,0.0)  #Trigger a node at time zero

executor = SerialExecutor()

#execute!(workflow,executor)

#step(workflow,executor)
# step(workflow,executor)

# connect(workflow,w2,w1)
# #@connect(workflow,w1 => [w2 w3])  #creates a default output channel to use
#
# trigger!(workflow,w1)

# executor = SerialExecutor(workflow)
#
# step(workflow)

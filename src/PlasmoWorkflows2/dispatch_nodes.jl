#A discrete node gets scheduled on edge triggering
mutable struct DispatchNode <: AbstractDispatchNode  #A Dispatch node
    basenode::BasePlasmoNode
    attributes::Vector{Attribute}
    priority::Int                               #Priority of signals this node produces
    local_time::Float64                         #The node's local clock.  Gets synchronized with the workflow clock on triggers
    compute_time::Float64                       #The time the node takes to complete its task.
    node_task::DispatchFunction                 #the actual function (task) to call
    state_manager::StateManager
    initial_signal::Union{Void,Signal}
end
#Constructor -- Maybe need an inner constructor
function DispatchNode()
    basenode = BasePlasmoNode()
    attributes = [Attribute(:result)]
    local_time = 0
    compute_time = 0
    node_task = DispatchFunction()


    state_manager = StateManger()
    setstates(state_manager,[:idle,:scheduled,:computing,:synchronizing,:error,:inactive])
    setstate(state_manager,:idle)
    return DispatchNode(basenode,attributes,0,local_time,compute_time,node_task,state_manager)
end
create_node(graph::Workflow) = DispatchNode()

#Dispatch node transitions
function add_dispatch_node!(workflow::Workflow)
    node = add_node!(workflow)
    state_manager = node.state_manager
    addtransition!(state_manager,State(:idle),Signal(:schedule),State(:scheduled), action = TransitionAction(schedule_node,workflow,node))  #no target for produced signal (so it won't schedule)
    addtransition!(state_manager,State(:idle),Signal(:execute),State(:computing), action = TransitionAction(run_node_task,workflow,node),targets = [node.state_manager])
    addtransition!(state_manager,State(:computing),Signal(:complete),State(:synchronizing), action = TransitionAction(synchronize_node,workflow,node), targets = [node.state_manager])
    addtransition!(state_manager,State(:synchronizing),Signal(:synchronized),State(:idle))#, action = synchronized)

    for state in [State(:idle),State(:computing),State(:synchronizing)]
        addtransition!(state_manager,state,Signal(:error),State(:error))
        addtransition!(state_manager,state,Signal(:disable),State(:inactive))
    end
    return node
end

#Continuous node transitions
function add_continuous_node!(workflow::Workflow)
    node = add_node!(workflow)
    return node
end

#Add an attribute.  Update node transitions for when attributes are added.
function addattribute!(workflow::Workflow,node::DispatchNode,label::Symbol,attribute::Any; update_notify_targets = SignalTarget[])
    attribute = Attribute(label,attribute,attribute)
    push!(node.attributes,attribute)
    addtransition!(node.state_manager,State(:synchronizing),Signal(:update_attribute,attribute),State(:synchronizing), action = TransitionAction(update_attribute,workflow,attribute),targets = update_notify_targets)
end



###########################
# Node Triggers
###########################
getsignals(node::DispatchNode) = getsignals(node.state_manager)

#addsignal!(node::DispatchNode,event::DataType) = push!(node.triggers,event)


getlocaltime(node::AbstractDispatchNode) = node.local_time
##########################
#Node Result
##########################
getresult(node::AbstractDispatchNode) = getresult(node.dispatch_function)


##########################
#Node Dispatch Function
##########################
set_node_task(node::AbstractDispatchNode,func::Function) = node.dispatch_function = DispatchFunction(func)
set_node_task_arguments(node::AbstractDispatchNode,args::Vector{Any}) = node.dispatch_function.args = args
set_node_task_arguments(node::AbstractDispatchNode,arg::Any) = node.dispatch_function.args = [arg]
set_node_task_kwargs(node::AbstractDispatchNode,kwargs::Dict{Any,Any}) = node.dispatch_function.kwargs = kwargs

set_node_compute_time(node::AbstractDispatchNode,time::Float64) = node.compute_time = time

########################################
#Connect Nodes with Communication Edges
########################################
function connect!(workflow::Workflow,dnode1::DispatchNode,dnode2::DispatchNode;delay = 0,communication_frequency = nothing)
    #is_connected(workflow,dnode1,dnode2) && throw("communication edge already exists between these nodes")

    #Default connection behavior
    comm_edge = add_edge!(workflow,dnode1,dnode2)
    setdelay(comm_edge,delay)
    if communication_frequency != nothing
        # Add state manager functions to the edge manager
        # set_trigger_frequency(comm_edge,communication_frequency)
        # settrigger(comm_edge,EdgeTriggerEvent)
    end
    addtransition!(state_manager,State(:idle),Signal(:comm_received),State(:idle),action = TransitionAction(receive_attribute,workflow),targets = [node.state_manager])

    return comm_edge
end

#A discrete node gets scheduled on edge triggering
mutable struct DispatchNode <: AbstractDispatchNode  #A Dispatch node
    basenode::BasePlasmoNode
    #attributes::Vector{Attribute}
    attributes::Dict{Symbol,Attribute}
    priority::Int                               #Priority of signals this node produces
    local_time::Float64                         #The node's local clock.  Gets synchronized with the workflow clock on triggers
    compute_time::Float64                       #The time the node takes to complete its task.
    schedule_delay::Float64
    node_task::DispatchFunction                 #the actual function (task) to call
    state_manager::StateManager

    function DispatchNode()
        node = new()
        node.basenode = BasePlasmoNode()
        result_attribute = Attribute(node,:result)
        node.attributes = Dict(:result => result_attribute)
        node.local_time = 0
        node.compute_time = 0
        node.schedule_delay = 0
        node.node_task = DispatchFunction()
        node.state_manager = StateManager()
        setstates(node.state_manager,[:null,:idle,:scheduled,:computing,:synchronizing,:error,:inactive])
        setstate(node.state_manager,:idle)
        return node
    end
end
PlasmoGraphBase.create_node(graph::Workflow) = DispatchNode()

#Dispatch node runs when it gets communication updates
function add_dispatch_node!(workflow::Workflow)
    node = add_node!(workflow)
    state_manager = node.state_manager
    addtransition!(state_manager,State(:idle),Signal(:schedule),State(:scheduled), action = TransitionAction(schedule_node,[node]))  #no target for produced signal (so it won't schedule)
    addtransition!(state_manager,State(:scheduled),Signal(:execute),State(:computing), action = TransitionAction(run_node_task,[node]),targets = [node.state_manager])  #no target for produced signal (so it won't schedule)
    addtransition!(state_manager,State(:idle),Signal(:execute),State(:computing), action = TransitionAction(run_node_task,[node]),targets = [node.state_manager])
    addtransition!(state_manager,State(:computing),Signal(:complete),State(:synchronizing), action = TransitionAction(synchronize_node,[node]), targets = [node.state_manager])
    addtransition!(state_manager,State(:synchronizing),Signal(:synchronized),State(:idle))  #Node is complete
    #result attribute update
    result_attribute = getattribute(node,:result)
    addtransition!(node.state_manager,State(:synchronizing),Signal(:synchronize_attribute,result_attribute),State(:synchronizing), action = TransitionAction(synchronize_attribute, [result_attribute]))


    for state in [State(:idle),State(:computing),State(:synchronizing)]
        addtransition!(state_manager,state,Signal(:error),State(:error))
        addtransition!(state_manager,state,Signal(:disable),State(:inactive))
    end
    return node
end

#Continuous node transitions
function add_continuous_node!(workflow::Workflow)
    node = add_node!(workflow)
    state_manager = node.state_manager
    addtransition!(state_manager,State(:idle),Signal(:schedule),State(:scheduled), action = TransitionAction(schedule_node,[node]))  #no target for produced signal (so it won't schedule)
    addtransition!(state_manager,State(:scheduled),Signal(:execute),State(:computing), action = TransitionAction(run_node_task,[node]),targets = [node.state_manager])  #no target for produced signal (so it won't schedule)
    addtransition!(state_manager,State(:idle),Signal(:execute),State(:computing), action = TransitionAction(run_node_task,[node]),targets = [node.state_manager])
    addtransition!(state_manager,State(:computing),Signal(:complete),State(:synchronizing), action = TransitionAction(synchronize_node,[node]), targets = [node.state_manager])
    addtransition!(state_manager,State(:synchronizing),Signal(:synchronized),State(:scheduled), action = TransitionAction(schedule_node,[node]))  #Node reschedules

    result_attribute = getattribute(node,:result)
    addtransition!(node.state_manager,State(:synchronizing),Signal(:synchronize_attribute,result_attribute),State(:synchronizing), action = TransitionAction(synchronize_attribute, [result_attribute]))


    for state in [State(:idle),State(:computing),State(:synchronizing)]
        addtransition!(state_manager,state,Signal(:error),State(:error))
        addtransition!(state_manager,state,Signal(:disable),State(:inactive))
    end
    return node
end

#Add an attribute.  Update node transitions for when attributes are added.
function addattribute!(node::DispatchNode,label::Symbol,attribute::Any; update_notify_targets = SignalTarget[])
    workflow_attribute = Attribute(node,label,attribute,attribute)
    node.attributes[label] = workflow_attribute
    #Attributes can be updated when a node is in a synchronizing state
    addtransition!(node.state_manager,State(:synchronizing),Signal(:synchronize_attribute,workflow_attribute),State(:synchronizing), action = TransitionAction(synchronize_attribute, [workflow_attribute]),targets = update_notify_targets)
    addtransition!(node.state_manager,State(:idle),Signal(:attribute_received,workflow_attribute),State(:scheduled), action = TransitionAction(schedule_node,[node]),targets = [node.state_manager])
    addtransition!(node.state_manager,State(:idle),Signal(:update_attribute,workflow_attribute),State(:idle), action = TransitionAction(update_attribute,[workflow_attribute]),targets = update_notify_targets)

end

function addattribute!(node::DispatchNode,label::Symbol; update_notify_targets = SignalTarget[])
    workflow_attribute = Attribute(node,label)
    node.attributes[label] = workflow_attribute
    addtransition!(node.state_manager,State(:synchronizing),Signal(:synchronize_attribute,workflow_attribute),State(:synchronizing), action = TransitionAction(synchronize_attribute, [workflow_attribute]),targets = update_notify_targets)
    addtransition!(node.state_manager,State(:idle),Signal(:attribute_received,workflow_attribute),State(:scheduled), action = TransitionAction(schedule_node,[node]),targets = [node.state_manager])
    addtransition!(node.state_manager,State(:idle),Signal(:update_attribute,workflow_attribute),State(:idle), action = TransitionAction(update_attribute,[workflow_attribute]),targets = update_notify_targets)

end

###########################
# Node functions
###########################
getlocaltime(node::AbstractDispatchNode) = node.local_time
getresult(node::AbstractDispatchNode) = getresult(node.dispatch_function)
getcomputetime(node::AbstractDispatchNode) = node.compute_time
getscheduledelay(node::AbstractDispatchNode) = node.schedule_delay

#Node State Manager
getsignals(node::DispatchNode) = getsignals(node.state_manager)
getinitialsignal(node::AbstractDispatchNode) = getinitialsignal(node.state_manager)
setinitialsignal(node::AbstractDispatchNode,signal::AbstractSignal) = setinitialsignal(node.state_manager,signal)
setinitialsignal(node::AbstractDispatchNode,signal::Symbol) = setinitialsignal(node.state_manager,Signal(signal))
getstatemanager(node::AbstractDispatchNode) = node.state_manager


getstates(node::AbstractDispatchNode) = getstates(node.state_manager)
gettransition(node::AbstractDispatchNode, state::State,signal::Signal) = gettransition(node.state_manager,state,signal)
gettransitions(node::AbstractDispatchNode) = gettransitions(node.state_manager)
getcurrentstate(node::AbstractDispatchNode) = getcurrentstate(node.state_manager)

getattribute(node::DispatchNode,label::Symbol) = node.attributes[label]
getattributes(node::DispatchNode) = node.attributes
setattribute(node::DispatchNode,label::Symbol,value::Any) = node.attributes[label].local_value = value
getindex(node::DispatchNode,sym::Symbol) = getattribute(node,sym)

##########################
#Node Task
##########################
set_node_task(node::AbstractDispatchNode,func::Function) = node.node_task = DispatchFunction(func)
set_node_task_arguments(node::AbstractDispatchNode,args::Vector{Any}) = node.node_task.args = args
set_node_task_arguments(node::AbstractDispatchNode,arg::Any) = node.node_task.args = [arg]
set_node_task_kwargs(node::AbstractDispatchNode,kwargs::Dict{Any,Any}) = node.node_task.kwargs = kwargs
set_node_compute_time(node::AbstractDispatchNode,time::Float64) = node.compute_time = time

########################################
#Connect Nodes with Communication Edges
########################################
function connect!(workflow::Workflow,attribute1::Attribute,attribute2::Attribute;comm_delay = 0,schedule_delay = 0,continuous = false)
    #is_connected(workflow,dnode1,dnode2) && throw("communication edge already exists between these nodes")
    #Default connection behavior
    if continuous == false
        comm_channel = add_dispatch_edge!(workflow,attribute1,attribute2,comm_delay = comm_delay,schedule_delay = schedule_delay)
    else
        comm_channel = add_continuous_edge!(workflow,attribute1,attribute2,comm_delay = comm_delay,schedule_delay = schedule_delay)
    end

    source_node = getnode(attribute1)
    receive_node = getnode(attribute2)
    state_manager = getstatemanager(receive_node)


    #broadcast source node transition to the channel
    transition_update = gettransition(source_node,State(:synchronizing),Signal(:synchronize_attribute,attribute1))  #This should return a comm_received signal
    addbroadcasttarget!(transition_update,comm_channel.state_manager)

    #Add receiving node transition
    #Transition: idle + comm_reeived ==> idle, action = received_attribute
    addtransition!(state_manager,State(:idle),Signal(:comm_received,attribute2),State(:idle),action = TransitionAction(update_attribute,[attribute2]),targets = [receive_node.state_manager])


    return comm_channel
end

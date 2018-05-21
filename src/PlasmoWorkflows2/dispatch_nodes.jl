#A discrete node gets scheduled on edge triggering
mutable struct DispatchNode <: AbstractDispatchNode  #A Dispatch node
    basenode::BasePlasmoNode
    #attributes::Vector{Attribute}
    attributes::Dict{Symbol,Attribute}
    priority::Int                               #Priority of signals this node produces
    local_time::Float64                         #The node's local clock.  Gets synchronized with the workflow clock on triggers
    compute_time::Float64                       #The time the node takes to complete its task.
    node_task::DispatchFunction                 #the actual function (task) to call
    state_manager::StateManager

    function DispatchNode()
        node = new()
        node.basenode = BasePlasmoNode()
        node.attributes = Dict(:result => Attribute(node,:result))
        node.local_time = 0
        node.compute_time = 0
        node.node_task = DispatchFunction()
        node.state_manager = StateManager()
        setstates(node.state_manager,[:null,:idle,:scheduled,:computing,:synchronizing,:error,:inactive])
        setstate(node.state_manager,:idle)
        return node
    end
end

# #Constructor -- Maybe need an inner constructor
# function DispatchNode()
#     basenode = BasePlasmoNode()
#     attributes = [Attribute(:result)]
#     local_time = 0
#     compute_time = 0
#     node_task = DispatchFunction()
#
#     state_manager = StateManger()
#     setstates(state_manager,[:idle,:scheduled,:computing,:synchronizing,:error,:inactive])
#     setstate(state_manager,:idle)
#     return DispatchNode(basenode,attributes,0,local_time,compute_time,node_task,state_manager)
# end
PlasmoGraphBase.create_node(graph::Workflow) = DispatchNode()

#Dispatch node runs when it gets communication updates
function add_dispatch_node!(workflow::Workflow)
    node = add_node!(workflow)
    state_manager = node.state_manager
    addtransition!(state_manager,State(:idle),Signal(:schedule),State(:scheduled), action = TransitionAction(schedule_node,[node]))  #no target for produced signal (so it won't schedule)
    addtransition!(state_manager,State(:idle),Signal(:execute),State(:computing), action = TransitionAction(run_node_task,[node]),targets = [node.state_manager])
    addtransition!(state_manager,State(:computing),Signal(:complete),State(:synchronizing), action = TransitionAction(synchronize_node,[node]), targets = [node.state_manager])
    addtransition!(state_manager,State(:synchronizing),Signal(:synchronized),State(:idle))  #Node is complete

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
    addtransition!(state_manager,State(:idle),Signal(:execute),State(:computing), action = TransitionAction(run_node_task,[node]),targets = [node.state_manager])
    addtransition!(state_manager,State(:computing),Signal(:complete),State(:synchronizing), action = TransitionAction(synchronize_node,[node]), targets = [node.state_manager])
    addtransition!(state_manager,State(:synchronizing),Signal(:synchronized),State(:scheduled), action = TransitionAction(schedule_node,[node]))  #Node reschedules

    for state in [State(:idle),State(:computing),State(:synchronizing)]
        addtransition!(state_manager,state,Signal(:error),State(:error))
        addtransition!(state_manager,state,Signal(:disable),State(:inactive))
    end
    return node
end

#Add an attribute.  Update node transitions for when attributes are added.
function addattribute!(node::DispatchNode,label::Symbol,attribute::Any; update_notify_targets = SignalTarget[])
    workflow_attribute = Attribute(node,label,attribute,attribute)
    #push!(node.attributes,workflow_attribute)
    node.attributes[label] = workflow_attribute
    #Add a transition action for when the attribute gets updated.
    addtransition!(node.state_manager,State(:synchronizing),Signal(:synchronize_attribute,attribute),State(:synchronizing), action = TransitionAction(synchronize_attribute, [workflow_attribute]),targets = update_notify_targets)
end

function addattribute!(node::DispatchNode,label::Symbol; update_notify_targets = SignalTarget[])
    workflow_attribute = Attribute(node,label)
    node.attributes[label] = workflow_attribute
    #push!(node.attributes,workflow_attribute)
    #Add a transition action for when the attribute gets updated.
    addtransition!(node.state_manager,State(:synchronizing),Signal(:synchronize_attribute,workflow_attribute),State(:synchronizing), action = TransitionAction(synchronize_attribute, [workflow_attribute]),targets = update_notify_targets)
end

###########################
# Node functions
###########################
getsignals(node::DispatchNode) = getsignals(node.state_manager)
getlocaltime(node::AbstractDispatchNode) = node.local_time
getresult(node::AbstractDispatchNode) = getresult(node.dispatch_function)
getinitialsignal(node::AbstractDispatchNode) = getinitialsignal(node.state_manager)
setinitialsignal(node::AbstractDispatchNode,signal::AbstractSignal) = setinitialsignal(node.state_manager,signal)
getstatemanager(node::AbstractDispatchNode) = node.state_manager

getattribute(node::DispatchNode,label::Symbol) = node.attributes[label]
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

    receive_node = getnode(attribute2)
    state_manager = getstatemanager(receive_node)
    #Transition: idle + comm_reeived ==> idle, action = received_attribute
    addtransition!(state_manager,State(:idle),Signal(:comm_received,attribute1),State(:idle),action = TransitionAction(received_attribute,[attribute1]),targets = [receive_node.state_manager])

    return comm_channel
end

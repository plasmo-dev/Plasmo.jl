#A discrete node gets scheduled on edge triggering
mutable struct DispatchNode <: AbstractDispatchNode  #A Dispatch node
    basenode::BasePlasmoNode
    attributes::Dict{Symbol,Attribute}
    #priority::Int                                  #Priority of signals this node produces
    node_tasks::Dict{Symbol,NodeTask}              #the actual function (tasks) to call
    state_manager::StateManager

    task_triggers::Dict{Attribute,NodeTask}

    task_results::Dict{NodeTask,Attribute}

    updated_attributes::Vector{Attribute}
    #signal_queue::Vector{AbstractSignal}
    #history::Union{Nothing,Vector{Tuple}}

    function DispatchNode()
        node = new()
        node.basenode = BasePlasmoNode()
        node.state_manager = StateManager()
        #result_attribute = Attribute(node,:result)
        node.attributes = Dict{Symbol,Attribute}()
        #node.last_result = nothing
        #node.local_time = 0
        node.node_tasks = Dict{Symbol,NodeTask}()

        node.action_triggers = Dict{Attribute,NodeTask}()
        node.task_results = Dict{NodeTask,Attribute}()
        node.updated_attributes = Attribute[]

        node.signal_queue = AbstractSignal[]
        node.history = nothing
        #setstates(node.state_manager,[:null,:idle,:scheduled,:computing,:synchronizing,:error,:inactive])
        addstates!(node.state_manager,[:idle,:inactive,:error])
        setstate(node.state_manager,:idle)
        # suppresssignal!(node.state_manager,Signal(:nothing))
        # suppresssignal!(node.state_manager,Signal(:signal_queued))
        return node
    end
end
PlasmoGraphBase.create_node(graph::Workflow) = DispatchNode()

#Dispatch node runs when it gets communication updates
function add_dispatch_node!(graph::ComutingGraph;store_history = true)#;continuous = false)
    node = add_node!(graph)
    store_history == true && (node.history = Vector{Tuple}())
    state_manager = node.state_manager
    addtransition!(state_manager,State(:idle),Signal(:error),State(:error))
    addtransition!(state_manager,State(:idle),Signal(:off),State(:inactive))

    #Set suppressed signals by default
    #suppresssignal!(state_manager,Signal(:scheduled,:Any))
    return node
end

addtransition!(node::DispatchNode) = addtransition!(node.state_manager,state1::State,signal::AbstractSignal,state2::State)

function addnodetask!(workflow::Workflow,node::DispatchNode,label::Symbol,func::Function;args = (),kwargs = Dict(),compute_time = 0.0,schedule_delay = 0.0,continuous = false,triggered_by_attributes = Vector{Attribute}())
    node_task = NodeTask(label,func,args = args,kwargs = kwargs,compute_time = compute_time,schedule_delay = schedule_delay)
    addnodetask!(workflow,node,node_task,continuous = continuous,triggered_by_attributes = triggered_by_attributes)
    return node_task
end

function addnodetask!(workflow::Workflow,node::DispatchNode,node_task::NodeTask;continuous = false,triggered_by_attributes = Vector{Attribute}())
    state_manager = getstatemanager(node)

    #Add task states
    #addstates!(node.state_manager,[State(:scheduled,node_task),State(:computing,node_task),State(:synchronizing,node_task)])
    addstates!(node.state_manager,[State(:computing,node_task),State(:synchronizing,node_task)])
    #Set suppressed signals by default
    suppresssignal!(state_manager,Signal(:scheduled,node_task))

    #Add the node transitions for this task
    #addtransition!(state_manager,State(:idle),Signal(:schedule,node_task),State(:scheduled,node_task), action = TransitionAction(schedule_node_task,[node_task]))  #no target for produced signal (so it won't schedule)
    addtransition!(state_manager,State(:idle),Signal(:schedule,node_task),State(:idle), action = TransitionAction(schedule_node_task,[node_task]))  #no target for produced signal (so it won't schedule)

    # addtransition!(state_manager,State(:scheduled,node_task),Signal(:execute,node_task),State(:computing,node_task),
    # action = TransitionAction(run_node_task,[workflow,node,node_task]),targets = [node.state_manager])  #no target for produced signal (so it won't schedule)

    addtransition!(state_manager,State(:idle),Signal(:execute,node_task),State(:executing,node_task),
    action = TransitionAction(execute_node_task,[graph,node,node_task]),targets = [node.state_manager])

    addtransition!(state_manager,State(:computing,node_task),Signal(:complete,node_task),State(:synchronizing,node_task),
    action = TransitionAction(synchronize_node_task,[node,node_task]), targets = [node.state_manager])

    addtransition!(state_manager,State(:synchronizing,node_task),Signal(:synchronized,node_task),State(:idle),
    action = TransitionAction(pop_node_queue,[node]),targets = [node.state_manager])  #Node is complete

    #Create a task result attribute
    result_attribute = addworkflowattribute!(node,Symbol(string(node_task.label)))
    node.task_results[node_task] = result_attribute

    #Add attribute transition for this task
    for workflow_attribute in getworkflowattributes(node)
        addtransition!(node.state_manager,State(:synchronizing,node_task),Signal(:synchronize_attribute,workflow_attribute),State(:synchronizing,node_task),
        action = TransitionAction(synchronize_attribute, [workflow_attribute]))#targets = update_notify_targets)
    end

    #Add optional continuous behavior
    if continuous == true
        #NOTE Check the node compute time.  Don't remember why I wrote this....
        make_continuous!(node,node_task)
    end

    #Add Error and Disable pathways for these task states
    # for state in [State(:scheduled,node_task),State(:computing,node_task),State(:synchronizing,node_task)]
    for state in [State(:computing,node_task),State(:synchronizing,node_task)]
        addtransition!(state_manager,state,Signal(:error),State(:error))
        addtransition!(state_manager,state,Signal(:disable),State(:inactive))
    end

    #Execute this node_task if triggered_by_attribute is received
    for workflow_attribute in triggered_by_attributes
        node.action_triggers[workflow_attribute] = node_task
        unsuppresssignal!(node.state_manager,Signal(:attribute_received,workflow_attribute))
        #addtransition!(node.state_manager,State(:idle),Signal(:attribute_received,workflow_attribute),State(:scheduled,node_task), action = TransitionAction(schedule_node_task,[node_task]),targets = [node.state_manager])
        addtransition!(node.state_manager,State(:idle),Signal(:attribute_received,workflow_attribute),State(:idle), action = TransitionAction(schedule_node_task,[node_task]),targets = [node.state_manager])

        #for task in getnodetasks(node)
        #NOTE THIS IS CAUSING PROBLEMS
        # addtransition!(node.state_manager,State(:synchronizing,node_task),Signal(:attribute_received,workflow_attribute),State(:synchronizing,node_task),
        # action = TransitionAction(schedule_node_task_during_synchronize,[node,node_task]),targets = [node.state_manager])

        #Allow trigger attributes to be received/updated in the scheduled state
        #addtransition!(node.state_manager,State(:scheduled,node_task),Signal(:attribute_received,workflow_attribute),State(:scheduled,node_task))
        #end
    end

    node.node_tasks[getlabel(node_task)] = node_task

    for task in getnodetasks(node)
        for attribute in keys(node.action_triggers)
            if haskey(node.action_triggers,attribute)
                addtransition!(node.state_manager,State(:synchronizing,task),Signal(:attribute_received,attribute),State(:synchronizing,task),
                action = TransitionAction(schedule_node_task_during_synchronize,[node,node.action_triggers[attribute]]),targets = [node.state_manager])
            end
        end
    end

    # for task in getnodetasks(node)
    #     for other_node_task in getnodetasks(node)
    #         addtransition!(node.state_manager,State(:synchronizing,task),Signal(:execute,other_node_task),State(:synchronizing,task),
    #         action = TransitionAction(schedule_node_task_during_synchronize,[node,other_node_task]),targets = [node.state_manager])
    #     end
    # end

end

#Make a node task run continuously based on its schedule delay
function make_continuous!(node::DispatchNode,node_task::NodeTask)
    transition = gettransition(node.state_manager,State(:synchronizing,node_task),Signal(:synchronized,node_task))
    settransitionaction(transition,TransitionAction(schedule_node_task,[node_task]))
    addbroadcasttarget!(transition,node.state_manager)
end

#Add an attribute.  Update node transitions for when attributes are added.
function addworkflowattribute!(node::DispatchNode,label::Symbol,attribute::Any; update_notify_targets = SignalTarget[])#,execute_on_receive = true)
    workflow_attribute = Attribute(node,label,attribute)
    node.attributes[label] = workflow_attribute

    #Attribute can be updated when a node is in a synchronizing state for any task
    for node_task in getnodetasks(node)
        addtransition!(node.state_manager,State(:synchronizing,node_task),Signal(:synchronize_attribute,workflow_attribute),State(:synchronizing,node_task), action = TransitionAction(synchronize_attribute, [workflow_attribute]),targets = update_notify_targets)
    end

    #TODO Signal Suppression
    #Ignore received attributes that don't trigger actions.  Suppress by default.
    suppresssignal!(node.state_manager,Signal(:attribute_received,workflow_attribute))

    #NOTE Old way of setting up attribute triggers
    #If true, schedule the node's task when it receives an attribute
    # if execute_on_receive == true
    #     addtransition!(node.state_manager,State(:idle),Signal(:attribute_received,workflow_attribute),State(:scheduled), action = TransitionAction(schedule_node,[node]),targets = [node.state_manager])
    # else
    #     suppresssignal!(node.state_manager,Signal(:attribute_received,workflow_attribute))
    # end

    #Update an attribute manually from the idle state
    addtransition!(node.state_manager,State(:idle),Signal(:update_attribute,workflow_attribute),State(:idle), action = TransitionAction(update_attribute,[workflow_attribute]),targets = update_notify_targets)
    #suppresssignal!(node.state_manager,Signal(:comm_sent,workflow_attribute))
    return workflow_attribute
end
addworkflowattribute!(node::DispatchNode,label::Symbol;update_notify_targets = SignalTarget[]) = addworkflowattribute!(node,label,nothing,update_notify_targets = update_notify_targets)

# function addattribute!(node::DispatchNode,label::Symbol; update_notify_targets = SignalTarget[])
#     workflow_attribute = Attribute(node,label)
#     node.attributes[label] = workflow_attribute
#     addtransition!(node.state_manager,State(:synchronizing),Signal(:synchronize_attribute,workflow_attribute),State(:synchronizing), action = TransitionAction(synchronize_attribute, [workflow_attribute]),targets = update_notify_targets)
#     addtransition!(node.state_manager,State(:idle),Signal(:attribute_received,workflow_attribute),State(:scheduled), action = TransitionAction(schedule_node,[node]),targets = [node.state_manager])
#     addtransition!(node.state_manager,State(:idle),Signal(:update_attribute,workflow_attribute),State(:idle), action = TransitionAction(update_attribute,[workflow_attribute]),targets = update_notify_targets)
#     #suppresssignal!(node.state_manager,Signal(:comm_sent,workflow_attribute))
# end

function addworkflowattributes!(node::DispatchNode,att_dict::Dict{Symbol,Any};execute_on_receive = true)
    for (key,value) in att_dict
        addworkflowattribute!(node,key,value,execute_on_receive = execute_on_receive)
    end
end

function addtrigger!(node::DispatchNode,node_task::NodeTask,workflow_attribute::Attribute)
    node.action_triggers[workflow_attribute] = node_task
    unsuppresssignal!(node.state_manager,Signal(:attribute_received,workflow_attribute))
    #addtransition!(node.state_manager,State(:idle),Signal(:attribute_received,workflow_attribute),State(:scheduled,node_task), action = TransitionAction(schedule_node_task,[node_task]),targets = [node.state_manager])
    addtransition!(node.state_manager,State(:idle),Signal(:attribute_received,workflow_attribute),State(:idle), action = TransitionAction(schedule_node_task,[node_task]),targets = [node.state_manager])
end


getworkflowattribute(node::DispatchNode,label::Symbol) = node.attributes[label]
getworkflowattributes(node::DispatchNode) = values(node.attributes)
setworkflowattribute(node::DispatchNode,label::Symbol,value::Any) = node.attributes[label].local_value = value



getnodetasks(node::DispatchNode) = values(node.node_tasks)
getnodetask(node::DispatchNode,label::Symbol) = node.node_tasks[label]

getnoderesult(node::DispatchNode,node_task::NodeTask) = node.task_results[node_task]
getnoderesult(node::DispatchNode,label::Symbol) = node.task_results[getnodetask(node,label)]

###########################
# Node functions
###########################
getlocaltime(node::AbstractDispatchNode) = node.state_manager.local_time
getlastresult(node::AbstractDispatchNode) = node.last_result

# getresult(node::AbstractDispatchNode) = getresult(node.dispatch_function)
# getcomputetime(node::AbstractDispatchNode) = node.compute_time
# getscheduledelay(node::AbstractDispatchNode) = node.schedule_delay

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


function getindex(node::DispatchNode,sym::Symbol)
    if sym in keys(node.attributes)
        return getworkflowattribute(node,sym)
    elseif sym in keys(node.basenode.attributes)
        return getattribute(node,sym)
    else
        error("node does not have attribute $sym")
    end
end

##########################
#Node Task
##########################
# set_node_task(node::AbstractDispatchNode,func::Function) = node.node_task = DispatchFunction(func)
# set_node_task_arguments(node::AbstractDispatchNode,args::Vector{Any}) = node.node_task.args = args
# set_node_task_arguments(node::AbstractDispatchNode,arg::Any) = node.node_task.args = [arg]
# set_node_task_kwargs(node::AbstractDispatchNode,kwargs::Dict{Any,Any}) = node.node_task.kwargs = kwargs
# set_node_compute_time(node::AbstractDispatchNode,time::Float64) = node.compute_time = time

########################################
#Connect Nodes with Communication Edges
########################################
function connect!(workflow::Workflow,attribute1::Attribute,attribute2::Attribute;send_attribute_updates = true,comm_delay = 0,schedule_delay = 0,continuous = false,start_time = 0)
    #is_connected(workflow,dnode1,dnode2) && throw("communication edge already exists between these nodes")

    #Default connection behavior
    comm_channel = add_dispatch_edge!(workflow,attribute1,attribute2,comm_delay = comm_delay,continuous = continuous,
    schedule_delay = schedule_delay,start_time = start_time)

    source_node = getnode(attribute1)
    receive_node = getnode(attribute2)
    state_manager = getstatemanager(receive_node)

    #broadcast source node attribute update to the channel
    if send_attribute_updates == true
        for node_task in getnodetasks(source_node)
            transition_update = gettransition(source_node,State(:synchronizing,node_task),Signal(:synchronize_attribute,attribute1))  #returns attribute_updated signal
            addbroadcasttarget!(transition_update,comm_channel.state_manager)
        end
    end



    #Add receiving node transition
    #Transition: idle + comm_reeived ==> idle, action = received_attribute
    addtransition!(state_manager,State(:idle),Signal(:comm_received,attribute2),State(:idle),action = TransitionAction(receive_attribute,[attribute2]),targets = [receive_node.state_manager])

    #NOTE: Working on case when data arrives during sychronization


    #NOTE Commenting to remove :scheduled state
    #Receive an update while the node is still scheduled
    for node_task in getnodetasks(receive_node)
        #Allow attributes to be received while in the scheduled state
        addtransition!(state_manager,State(:synchronizing,node_task),Signal(:comm_received,attribute2),State(:synchronizing,node_task),
        action = TransitionAction(receive_attribute,[attribute2]),targets = [receive_node.state_manager])

        #NOTE THIS WAS CAUSING PROBLEMS
        # addtransition!(state_manager,State(:synchronizing,node_task),Signal(:attribute_received,attribute2),State(:synchronizing,node_task),
        # action = TransitionAction(schedule_node_task_during_synchronize,[receive_node,node_task]),targets = [receive_node.state_manager])

        # addtransition!(state_manager,State(:scheduled,node_task),Signal(:comm_received,attribute2),State(:scheduled,node_task),action = TransitionAction(receive_attribute,[attribute2]),targets = [receive_node.state_manager])
        #
        # #Schedule more executions when another attribute gets updated
        # addtransition!(state_manager,State(:scheduled,node_task),Signal(:attribute_received,attribute2),State(:scheduled,node_task), action = TransitionAction(schedule_node_task,[node_task]),targets = [receive_node.state_manager])
    end



    push!(attribute1.out_channels,comm_channel)
    push!(attribute2.in_channels,comm_channel)

    return comm_channel
end

#signal_queue::Vector{AbstractSignal}
#history::Union{Nothing,Vector{Tuple}}
#priority::Int                                  # Priority of signals this node produces
mutable struct ComputeNode <: AbstractComputeNode  #A Dispatch node
    basenode::BasePlasmoNode
    state_manager::StateManager                     # Underlying state manager

    attributes::Vector{NodeAttribute}
    attribute_map::Dict{Symbol,NodeAttribute}

    node_tasks::Vector{NodeTask}                     #  Tasks this node can run
    node_tasks::Dict{Symbol,NodeTask}                #
#   task_triggers::Dict{AbstractSignal,NodeTask}    # Signals can trigger tasks
    task_result_attributes::Dict{NodeTask,Attribute} # Result attribute for a task

    local_attributes_updated::Vector{Attribute}      # attributes with updated local values
    history::Vector{Tuple}

    task_queue::DataStructures.PriorityQueue{NodeTask,TaskPriority} # Node contains a queue of tasks to execute

    function ComputeNode()
        node = new()
        node.basenode = BasePlasmoNode()
        node.state_manager = StateManager()
        node.attributes = Dict{Symbol,Attribute}()
        node.node_tasks = Dict{Symbol,NodeTask}()
        node.action_triggers = Dict{Attribute,NodeTask}()
        node.task_results = Dict{NodeTask,Attribute}()
        node.updated_attributes = Attribute[]
        node.history =  Vector{Tuple}()
        addstates!(node.state_manager,[state_idle(),state_error(),state_inactive()])
        setstate(node.state_manager,state_idle())
        return node
    end
end
PlasmoGraphBase.create_node(graph::ComputingGraph) = ComputeNode()

#Dispatch node runs when it gets communication updates
function addnode!(graph::ComutingGraph)#;continuous = false)
    node = add_node!(graph)
    addtransition!(node,state_any(),signal_error(),state_error()))
    addtransition!(node,state_any(),signal_inactive(),state_inactive())
    return node
end
addtransition!(node::ComputeNode) = addtransition!(node.state_manager,state1::State,signal::AbstractSignal,state2::State)

function queue_node_task(node_task::NodeTask)
    node = getnode(node_task)
    queuetask!(node,node_task)
end


#Add node tasks to compute nodes

function addnodetask!(graph::ComputingGraph,node::ComputeNode,label::Symbol,func::Function;args = (),kwargs = Dict(),
    compute_time::Float64 = 0.0,triggered_by = Vector{Signal}())  #can be triggered by attribute signals

    node_task = NodeTask(label,func,args = args,kwargs = kwargs,compute_time = compute_time,schedule_delay = schedule_delay)

    addnodetask!(graph,node,node_task,continuous = continuous,triggered_by_attributes = triggered_by_attributes)
    return node_task
end

function addnodetask!(graph::ComputingGraph,node::ComputeNode,node_task::NodeTask;triggered_by::Vector{Signal} = Vector{Signal}())
    state_manager = getstatemanager(node)

    #Add task states
    #addstates!(node.state_manager,[State(:scheduled,node_task),State(:computing,node_task),State(:synchronizing,node_task)])
    addstates!(node,executing(node_task),finalizing(node_task))
    #Set suppressed signals by default
    #suppresssignal!(state_manager,Signal(:scheduled,node_task))

    #Add the node transitions for this task
    #addtransition!(state_manager,State(:idle),Signal(:schedule,node_task),State(:scheduled,node_task), action = TransitionAction(schedule_node_task,[node_task]))  #no target for produced signal (so it won't schedule)
    addtransition!(node,state_any(),signal_schedule(node_task),state_any(),action = action_schedule_node_task(node_task))  #no target for produced signal (so it won't schedule)

    # addtransition!(state_manager,State(:scheduled,node_task),Signal(:execute,node_task),State(:computing,node_task),
    # action = TransitionAction(run_node_task,[graph,node,node_task]),targets = [node.state_manager])  #no target for produced signal (so it won't schedule)

    addtransition!(state_manager,State(:idle),Signal(:execute,node_task),State(:executing,node_task),
    action = TransitionAction(execute_node_task,[graph,node,node_task]),targets = [node.state_manager])

    addtransition!(state_manager,State(:computing,node_task),Signal(:complete,node_task),State(:synchronizing,node_task),
    action = TransitionAction(synchronize_node_task,[node,node_task]), targets = [node.state_manager])

    addtransition!(state_manager,State(:synchronizing,node_task),Signal(:synchronized,node_task),State(:idle),
    action = TransitionAction(pop_node_queue,[node]),targets = [node.state_manager])  #Node is complete

    #Create a task result attribute
    result_attribute = addattribute!(node,Symbol(string(node_task.label)))
    node.task_results[node_task] = result_attribute

    #Add attribute transition for this task
    for workflow_attribute in getattributes(node)
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

function next_task!(node::ComputeNode)
    task = getnextask!(node.task_queue)
    return task
end

#Make a node task run continuously based on its schedule delay
function make_continuous!(node::ComputeNode,node_task::NodeTask)
    transition = gettransition(node.state_manager,State(:synchronizing,node_task),Signal(:synchronized,node_task))
    settransitionaction(transition,TransitionAction(schedule_node_task,[node_task]))
    addbroadcasttarget!(transition,node.state_manager)
end

#Add an attribute.  Update node transitions for when attributes are added.
function addattribute!(node::ComputeNode,label::Symbol,attribute::Any)#; update_notify_targets = SignalTarget[])   #,execute_on_receive = true)
    attribute = NodeAttribute(node,label,attribute)
    node.attributes[label] = attribute
    return attribute
end
addattribute!(node::ComputeNode,label::Symbol) = addattribute!(node,label,nothing)
#addattribute!(node::ComputeNode,label::Symbol;update_notify_targets = SignalTarget[]) = addattribute!(node,label,nothing,update_notify_targets = update_notify_targets)

function addattributes!(node::ComputeNode,att_dict::Dict{Symbol,Any};execute_on_receive = true)
    for (key,value) in att_dict
        addattribute!(node,key,value,execute_on_receive = execute_on_receive)
    end
end

function addtrigger!(node::ComputeNode,node_task::NodeTask,workflow_attribute::Attribute)
    node.action_triggers[workflow_attribute] = node_task
    unsuppresssignal!(node.state_manager,Signal(:attribute_received,workflow_attribute))
    #addtransition!(node.state_manager,State(:idle),Signal(:attribute_received,workflow_attribute),State(:scheduled,node_task), action = TransitionAction(schedule_node_task,[node_task]),targets = [node.state_manager])
    addtransition!(node.state_manager,State(:idle),Signal(:attribute_received,workflow_attribute),State(:idle), action = TransitionAction(schedule_node_task,[node_task]),targets = [node.state_manager])
end


getattribute(node::ComputeNode,label::Symbol) = node.attributes[label]
getattributes(node::ComputeNode) = values(node.attributes)
setattribute(node::ComputeNode,label::Symbol,value::Any) = node.attributes[label].local_value = value



getnodetasks(node::ComputeNode) = values(node.node_tasks)
getnodetask(node::ComputeNode,label::Symbol) = node.node_tasks[label]

getnoderesult(node::ComputeNode,node_task::NodeTask) = node.task_results[node_task]
getnoderesult(node::ComputeNode,label::Symbol) = node.task_results[getnodetask(node,label)]

###########################
# Node functions
###########################
getlocaltime(node::AbstractComputeNode) = node.state_manager.local_time
getlastresult(node::AbstractComputeNode) = node.last_result

# getresult(node::AbstractComputeNode) = getresult(node.dispatch_function)
# getcomputetime(node::AbstractComputeNode) = node.compute_time
# getscheduledelay(node::AbstractComputeNode) = node.schedule_delay

#Node State Manager
getsignals(node::ComputeNode) = getsignals(node.state_manager)
getinitialsignal(node::AbstractComputeNode) = getinitialsignal(node.state_manager)
setinitialsignal(node::AbstractComputeNode,signal::AbstractSignal) = setinitialsignal(node.state_manager,signal)
setinitialsignal(node::AbstractComputeNode,signal::Symbol) = setinitialsignal(node.state_manager,Signal(signal))
getstatemanager(node::AbstractComputeNode) = node.state_manager


getstates(node::AbstractComputeNode) = getstates(node.state_manager)
gettransition(node::AbstractComputeNode, state::State,signal::Signal) = gettransition(node.state_manager,state,signal)
gettransitions(node::AbstractComputeNode) = gettransitions(node.state_manager)
getcurrentstate(node::AbstractComputeNode) = getcurrentstate(node.state_manager)

#TODO: Make sure this works
function getindex(node::ComputeNode,sym::Symbol)
    if sym in keys(node.attributes)
        return getattribute(node,sym)
    elseif sym in keys(node.basenode.attributes)
        return getattribute(node,sym)
    else
        error("node does not have attribute $sym")
    end
end

function Base.setindex()
end

########################################
#Connect Nodes with Communication Edges
########################################
function connect!(workflow::ComputingGraph,attribute1::Attribute,attribute2::Attribute;send_attribute_updates = true,comm_delay = 0,schedule_delay = 0,continuous = false,start_time = 0)
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

# function getgraph(node::ComputeNode)
#     index = node.basenode.indices

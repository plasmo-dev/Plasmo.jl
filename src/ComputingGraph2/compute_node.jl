#signal_queue::Vector{AbstractSignal}
#history::Union{Nothing,Vector{Tuple}}
#priority::Int                                  # Priority of signals this node produces
mutable struct ComputeNode <: AbstractComputeNode  #A Dispatch node
    basenode::BasePlasmoNode
    state_manager::StateManager                      # Underlying state manager

    attributes::Vector{NodeAttribute}                # All node computing attributes
    attribute_map::Dict{Symbol,NodeAttribute}

    node_tasks::Vector{NodeTask}                     #  Tasks this node can run
    node_task_map::Dict{Symbol,NodeTask}             #

    task_result_attributes::Dict{NodeTask,Attribute} # Result attribute for a task
    local_attributes_updated::Vector{Attribute}      # attributes with updated local values
    history::Vector{Tuple}

    task_queue::DataStructures.PriorityQueue{NodeTask,Int64} # Node contains a queue of tasks to execute

    function ComputeNode()
        node = new()
        node.basenode = BasePlasmoNode()
        node.state_manager = StateManager()
        node.attributes = Dict{Symbol,Attribute}()
        node.node_tasks = Dict{Symbol,NodeTask}()
        node.attribute_triggers = Dict{Signal,NodeTask}()
        node.task_queue = DataStructures.PriorityQueue{NodeTask,Int64}()
        node.task_results = Dict{NodeTask,Attribute}()
        node.local_attribute_updates = NodeAttribute[]
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

    #error
    addtransition!(node,state_any(),signal_error(),state_error()))

    #inactive
    addtransition!(node,state_any(),signal_inactive(),state_inactive())
    return node
end

addtransition!(node::ComputeNode,state1::State,signal::AbstractSignal,state2::State;action::{Union{Nothing,NodeAction}} = nothing) = addtransition!(node.state_manager,state1,signal,state2,action = action)

function queuenodetask!(node_task::NodeTask)
    node = getnode(node_task)
    priority = length(node.task_queue)
    enqueue!(node.task_queue,node_task,priority)
end

#Add node tasks to compute nodes
function addnodetask!(graph::ComputingGraph,node::ComputeNode,label::Symbol,func::Function;args = (),kwargs = Dict(),
    compute_time::Float64 = mincomputetime(),triggered_by = Vector{Signal}())  #can be triggered by attribute signals
    node_task = NodeTask(node,label,func,args,kwargs,nothing,compute_time)#,schedule_delay = schedule_delay)
    addnodetask!(graph,node,node_task,triggered_by = triggered_by)
    return node_task
end

function addnodetask!(graph::ComputingGraph,node::ComputeNode,node_task::NodeTask;triggered_by::Vector{Signal} = Vector{Signal}())
    #state_manager = getstatemanager(node)

    #Add task states
    addstates!(node,state_executing(node_task),state_finalizing(node_task))
    #Add the node transitions for this task

    #schedule a task
    addtransition!(node,state_any(),signal_schedule(node_task),state_any(),action = action_schedule_node_task(node_task))  #no target for produced signal (so it won't schedule)

    #execute from idle
    addtransition!(node,state_idle(),signal_execute(node_task),state_executing(node_task),action = action_execute_node_task(node_task))#,targets = [node.state_manager])

    #finalize a task
    addtransition!(node,state_executing(node_task),signal_finalize(node_task),state_finalizing(node_task),action = action_finalize_node_task(node_task))

    #back to idle
    addtransition!(node,state_finalizing(node_task),signal_back_to_idle(),state_idle(),action = action_execute_next_task())

    #Create a task result attribute
    result_attribute = addattribute!(node,Symbol(string(node_task.label)))
    node.task_results[node_task] = result_attribute

    for signal in triggered_by

        #node.action_triggers[workflow_attribute] = node_task #NOTE Consider removing

        #Execute on attribute signal from idle
        addtransition!(node,state_idle(),signal,state_executing(node_task),action = action_execute_node_task(node_task))

        #Queue on attribute signal if not idle
        addtransition!(node,state_executing(),signal,state_executing(),action = action_queue_node_task(node_task))
        addtransition!(node,state_finalizing(),signal,state_finalizing(),action = action_queue_node_task(node_task))
    end
    node.node_tasks[getlabel(node_task)] = node_task
end

function addtasktrigger!(node::ComputeNode,node_task::NodeTask,signal::Signal)
    push!(node.task_triggers[node_task],signal)

    #execute if in idle
    addtransition!(node,state_idle(),signal,state_executing(node_task), action = action_execute_node_task(node_task)

    #queue if executing
    addtransition!(node,state_executing(),signal,state_executing(), action = action_queue_node_task(node_task))

    #queue if finalizing
    addtransition!(node,state_finalizing(),signal,state_finalizing(),action = action_queue_node_task(node_task))
end


next_task(node::ComputeNode) = peek(node.task_queue)
next_task!(node::ComputeNode) = dequeue!(node.task_queue)

#Add an attribute.  Update node transitions for when attributes are added.
function addcomputeattribute!(node::ComputeNode,label::Symbol,value::Any)#; update_notify_targets = SignalTarget[])   #,execute_on_receive = true)
    attribute = NodeAttribute(node,label,value)
    node.attributes[label] = attribute
    return attribute
end
addcomputeattribute!(node::ComputeNode,label::Symbol) = addcomputeattribute!(node,label,nothing)

function addcomputeattributes!(node::ComputeNode,values::Dict{Symbol,Any})
    for (key,value) in values
        addcomputeattribute!(node,key,value)
    end
end


getcomputeattribute(node::ComputeNode,label::Symbol) = node.attribute_map[label]
getcomputeattributes(node::ComputeNode) = node.attributes

function setglobalvalue(node::ComputeNode,label::Symbol,value::Any)
    attribute = node.attribute_map[label]
    attribute.local_value = value
    attribute.global_value = value
end

getnodetasks(node::ComputeNode) = node.node_tasks
getnodetask(node::ComputeNode,label::Symbol) = node.node_task_map[label]

getnoderesult(node::ComputeNode,node_task::NodeTask) = node.task_results[node_task]
getnoderesult(node::ComputeNode,label::Symbol) = node.task_results[getnodetask(node,label)]

###########################
# Node functions
###########################
getlocaltime(node::AbstractComputeNode) = node.state_manager.local_time
#getlastresult(node::AbstractComputeNode) = node.last_result

#Node State Manager
getsignals(node::ComputeNode) = getsignals(node.state_manager)
getstatemanager(node::AbstractComputeNode) = node.state_manager

getstates(node::AbstractComputeNode) = getstates(node.state_manager)
gettransition(node::AbstractComputeNode, state::State,signal::Signal) = gettransition(node.state_manager,state,signal)
gettransitions(node::AbstractComputeNode) = gettransitions(node.state_manager)
getcurrentstate(node::AbstractComputeNode) = getcurrentstate(node.state_manager)

#TODO: Make sure this works
function getindex(node::ComputeNode,sym::Symbol)
    if sym in keys(node.attributes)
        return getcomputeattribute(node,sym)
    elseif sym in keys(node.basenode.attributes)
        return getattribute(node,sym)
    else
        error("node does not have attribute $sym")
    end
end

function Base.setindex()
end

########################################
#Connect Node Attributes
########################################
#NOTE: Might be able to replace with just add_edge!
# function connect!(graph::ComputingGraph,attribute1::Attribute,attribute2::Attribute)#;send_attribute_updates = true,comm_delay = 0,schedule_delay = 0,continuous = false,start_time = 0)
#     #is_connected(workflow,dnode1,dnode2) && throw("communication edge already exists between these nodes")
#     edge = add_edge!(graph,attribute1,attribute2)
#
#     push!(attribute1.out_edges,edge)
#     push!(attribute2.in_edges,edge)
#
#     return edge
# end

# function getgraph(node::ComputeNode)
#     index = node.basenode.indices

# for task in getnodetasks(node)
#     for other_node_task in getnodetasks(node)
#         addtransition!(node.state_manager,State(:synchronizing,task),Signal(:execute,other_node_task),State(:synchronizing,task),
#         action = TransitionAction(schedule_node_task_during_synchronize,[node,other_node_task]),targets = [node.state_manager])
#     end
# end



    #Add attribute transition for this task
    # for attribute in getcomputingattributes(node)
    #     addtransition!(node.state_manager,State(:synchronizing,node_task),Signal(:synchronize_attribute,workflow_attribute),State(:synchronizing,node_task),
    #     action = TransitionAction(synchronize_attribute, [workflow_attribute]))#targets = update_notify_targets)
    # end

    #Add optional continuous behavior
    # if continuous == true
    #     #NOTE Check the node compute time.  Don't remember why I wrote this....
    #     make_continuous!(node,node_task)
    # end

    #Add Error and Disable pathways for these task states
    # for state in [State(:scheduled,node_task),State(:computing,node_task),State(:synchronizing,node_task)]
    # for state in [State(:computing,node_task),State(:synchronizing,node_task)]
    #     addtransition!(state_manager,state,Signal(:error),State(:error))
    #     addtransition!(state_manager,state,Signal(:disable),State(:inactive))
    # end

    #Execute this node_task if triggered_by_attribute is received

    # source_node = getnode(attribute1)
    # receive_node = getnode(attribute2)

    #state_manager = getstatemanager(receive_node)

    # #broadcast source node attribute update to the channel
    # if send_attribute_updates == true
    #     for node_task in getnodetasks(source_node)
    #         transition_update = gettransition(source_node,State(:synchronizing,node_task),Signal(:synchronize_attribute,attribute1))  #returns attribute_updated signal
    #         addbroadcasttarget!(transition_update,comm_channel.state_manager)
    #     end
    # end

    #addtransition!(state_manager,State(:idle),Signal(:comm_received,attribute2),State(:idle),action = TransitionAction(receive_attribute,[attribute2]),targets = [receive_node.state_manager])

    #Add receiving node transition
    #Transition: idle + comm_reeived ==> idle, action = received_attribute

    #Add receive attribute transition if attribute receive triggers




    # #NOTE: Working on case when data arrives during sychronization
    # for node_task in getnodetasks(receive_node)
    #     #Allow attributes to be received while in the scheduled state
    #     addtransition!(state_manager,State(:synchronizing,node_task),Signal(:comm_received,attribute2),State(:synchronizing,node_task),
    #     action = TransitionAction(receive_attribute,[attribute2]),targets = [receive_node.state_manager])
    #
    #     #NOTE THIS WAS CAUSING PROBLEMS
    #     # addtransition!(state_manager,State(:synchronizing,node_task),Signal(:attribute_received,attribute2),State(:synchronizing,node_task),
    #     # action = TransitionAction(schedule_node_task_during_synchronize,[receive_node,node_task]),targets = [receive_node.state_manager])
    #
    #     # addtransition!(state_manager,State(:scheduled,node_task),Signal(:comm_received,attribute2),State(:scheduled,node_task),action = TransitionAction(receive_attribute,[attribute2]),targets = [receive_node.state_manager])
    #     #
    #     # #Schedule more executions when another attribute gets updated
    #     # addtransition!(state_manager,State(:scheduled,node_task),Signal(:attribute_received,attribute2),State(:scheduled,node_task), action = TransitionAction(schedule_node_task,[node_task]),targets = [receive_node.state_manager])
    # end

    #Make a node task run continuously based on its schedule delay
    # function make_continuous!(node::ComputeNode,node_task::NodeTask)
    #     transition = gettransition(node.state_manager,State(:synchronizing,node_task),Signal(:synchronized,node_task))
    #     settransitionaction(transition,TransitionAction(schedule_node_task,[node_task]))
    #     addbroadcasttarget!(transition,node.state_manager)
    # end

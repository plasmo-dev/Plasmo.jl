##########################
# Communication Edges
#########################
mutable struct CommunicationEdge <: AbstractCommunicationEdge
    state_manager::StateManager
    from_attribute::Attribute
    to_attribute::Attribute
    attribute_pipeline::Vector{EdgeAttribute}
    delay::Float64                       #communication delay
    history::Vector{Tuple}
end
#schedule_delay::Float64
#priority::Int            #signal priority (might make this event specific)

function CommunicationEdge()
    baseedge = BasePlasmoEdge()
    return CommunicationEdge(baseedge,channels)
end
PlasmoGraphBase.create_edge(graph::Workflow) = CommunicationEdge()   #PlasmoGraphBase edge construction

#getchannels(edge::AbstractCommunicationEdge) = edge.channels
getdelay(edge::AbstractCommunicationEdge,channel::Int) = edge.channels[channel].delay
getdelay(channel::CommunicationEdge) = channel.delay
isactive(channel::CommunicationEdge) = channel.state_manager.state == State(:active)
getsignals(channel::CommunicationEdge) = getsignals(channel.state_manager)
getinitialsignal(channel::AbstractCommunicationEdge) = getinitialsignal(channel.state_manager)
setinitialsignal(channel::AbstractCommunicationEdge,signal::AbstractSignal) = setinitialsignal(channel.state_manager,signal)
setinitialsignal(channel::AbstractCommunicationEdge,signal::Symbol) = setinitialsignal(channel.state_manager,Signal(signal))
getstatemanager(channel::AbstractCommunicationEdge) = channel.state_manager

getstates(channel::AbstractCommunicationEdge) = getstates(channel.state_manager)
gettransitions(channel::AbstractCommunicationEdge) = gettransitions(channel.state_manager)
getcurrentstate(channel::AbstractCommunicationEdge) = getcurrentstate(channel.state_manager)
getlocaltime(channel::AbstractCommunicationEdge) = channel.state_manager.local_time

setdelay(edge::AbstractCommunicationEdge,channel::Int,delay::Float64) = edge.channels[channel].delay = delay

#dispatch edge communicates when it receives attribute updates
function add_edge!(graph::AbstractComputingGraph,attribute1::Attribute,attribute2::Attribute;
    send_attribute_updates = true, delay = 0,send_on_signals = AttributeSignal[],send_wait = 0, start_time = 0)

    edge = add_edge!(graph,getnode(attribute1),getnode(attribute2))
    edge.send_triggers = send_on_signals


    edge_manager = getstatemanager(edge)
    destination_node = getnode(attribute2)

    for signal in edge.send_triggers
        t1 = addtransition!(edge_manager,State(:idle),signal,State(:communicating))
        t2 = addtransition!(edge_manager,State(:communicating),signal,State(:communicating))
        action = TransitionAction(schedule_communicate,[graph,edge,send_wait]))
        setaction(edge_manager,t1,action)
        setaction(edge_manager,t2,action)
    end

    #run communication when given :communicate signal
    t3 = addtransition!(edge_manager,State(:idle), Signal(:communicate), State(:communicating)
    t4 = addtransition!(edge_manager,State(:communicating),Signal(:communicate),State(:communicating))
    action = TransitionAction(communicate,[graph,edge])
    setaction(t3,action)
    setaction(t4,action)

    return edge
end

function addattribute!(edge::CommunicationEdge,label::Symbol,value::Any)#; update_notify_targets = SignalTarget[])   #,execute_on_receive = true)
    attribute = EdgeAttribute(edge,label,attribute)
    push!(edge.attribute_pipeline,attribute)
    return attribute
end

function removeattribute!(edge::CommunicationEdge,attribute::EdgeAttribute)
    filter!(x->x != attribute,edge.attribute_pipeline)
end

#schedulesignal(workflow,Signal(:communicate),channel,start_time)
# communicate in response to a send signal
# if continuous == true
#     comm_signal = sent(attribute1)
#
#     addtransition!(edge_manager,State(:idle),comm_signal,State(:communicating))
#     action = TransitionAction(schedule_communicate,[graph,edge,schedule_delay]))
#     addaction!(edge_manager,State(:idle),comm_signal)
#
#     schedulesignal(workflow,Signal(:communicate),channel,start_time)
#     queuesignal!(graph,Signal(:communicate),edge,nothing,start_time)
#
#     #suppresssignal!(channel.state_manager,Signal(:comm_received,attribute2))
# end

#TODO send attribute data when it updates
# if send_attribute_updates == true
#     addtransition!(edge.state_manager,State(:active), Signal(:attribute_updated,attribute1), State(:active),
#     action = TransitionAction(communicate,[workflow,channel]), targets = [destination_node.state_manager])
# end

# function addchannel!(edge::AbstractCommunicationEdge,from_attribute::Attribute,to_attribute::Attribute;comm_delay = 0,schedule_delay = 0,store_history = true)
#     channel = Channel(from_attribute,to_attribute,comm_delay,schedule_delay)
#     setstates(channel.state_manager,[:null,:active,:inactive,:error])
#     setstate(channel.state_manager,:active)
#     push!(edge.channels,channel)
#     store_history == true && (channel.history = Vector{Tuple}())
#     return channel
# end

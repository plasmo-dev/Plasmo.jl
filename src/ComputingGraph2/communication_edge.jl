##########################
# Communication Edges
#########################
mutable struct CommunicationEdge <: AbstractCommunicationEdge
    baseedge::BasePlasmoEdge
    state_manager::StateManager
    from_attribute::Union{Nothing,NodeAttribute}
    to_attribute::Union{Nothing,NodeAttribute}
    attribute_pipeline::Vector{EdgeAttribute}
    send_triggers::Vector{Signal}
    delay::Float64                       #communication delay
    history::Vector{Tuple}
    #local_time::Float64
end

function CommunicationEdge()
    edge = new()
    edge.baseedge = BasePlasmoEdge()
    edge.state_manager = StateManager()
    edge.from_attribute = nothing
    edge.to_attribute = nothing
    edge.attribute_pipeline = Vector{EdgeAttribute}()
    edge.send_triggers = Vector{Signal}()
    edge.delay = 0.0
    edge.history = Vector{Tuple}()
    return edge
end
PlasmoGraphBase.create_edge(graph::ComputingGraph) = CommunicationEdge()   #PlasmoGraphBase edge construction

#getchannels(edge::AbstractCommunicationEdge) = edge.channels
getdelay(edge::AbstractCommunicationEdge) = edge.delay
iscommunicating(edge::CommunicationEdge) = edge.state_manager.state == state_communicating()
getsignals(edge::CommunicationEdge) = getsignals(edge.state_manager)
getstatemanager(edge::AbstractCommunicationEdge) = edge.state_manager

getstates(edge::AbstractCommunicationEdge) = getstates(edge.state_manager)
gettransitions(edge::AbstractCommunicationEdge) = gettransitions(edge.state_manager)
getcurrentstate(edge::AbstractCommunicationEdge) = getcurrentstate(edge.state_manager)
#getlocaltime(edge::AbstractCommunicationEdge) = edge.local_time

setdelay(edge::AbstractCommunicationEdge,delay::Float64) = edge.delay = delay

#dispatch edge communicates when it receives attribute updates
function addedge!(graph::AbstractComputingGraph,attribute1::Attribute,attribute2::Attribute;
    delay::Number = 0,send_on = Signal[],send_delay::Number = 0.0)

    delay = Float64(delay)

    edge = add_edge!(graph,getnode(attribute1),getnode(attribute2))
    edge.from_attribute = attribute1
    edge.to_attribute = attribute2
    edge.send_triggers = send_on
    edge.delay = delay

    push!(attribute1.out_edges,edge)
    push!(attribute2.in_edges,edge)

    #communication actions
    addtransition!(edge,state_idle(), signal_communicate(), state_communicating();action = action_communicate())
    addtransition!(edge,state_communicating(),signal_communicate(),state_communicating())

    #schedule communication actions
    for signal in edge.send_triggers
        addtransition!(edge,state_idle(),signal,state_communicating(),action = action_schedule_communicate(send_delay))
        addtransition!(edge,state_communicating(),signal,state_communicating(),action = action_schedule_communicate(send_delay))
    end

    return edge
end

#setaction(edge,transition,schedule_communicate,delay)


function addcomputeattribute!(edge::CommunicationEdge,label::Symbol,value::Any)#; update_notify_targets = SignalTarget[])   #,execute_on_receive = true)
    attribute = EdgeAttribute(edge,label,value)
    push!(edge.attribute_pipeline,attribute)
    return attribute
end

function removecomputeattribute!(edge::CommunicationEdge,attribute::EdgeAttribute)
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

#schedule_delay::Float64
#priority::Int            #signal priority (might make this event specific)

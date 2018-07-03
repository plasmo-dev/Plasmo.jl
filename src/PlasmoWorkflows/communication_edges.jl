mutable struct Channel <: AbstractChannel
    state_manager::StateManager
    from_attribute::Attribute
    to_attribute::Attribute
    delay::Float64           #communication delay
    schedule_delay::Float64
    priority::Int            #signal priority (might make this event specific)
    history::Union{Void,Vector{Tuple}}
end
Channel(from_attribute::Attribute,to_attribute::Attribute) = Channel(StateManager(),from_attribute,to_attribute,0,0,0,nothing)
Channel(from_attribute::Attribute,to_attribute::Attribute,delay::Float64) = Channel(StateManager(),from_attribute,to_attribute,delay,0,0,nothing)
Channel(from_attribute::Attribute,to_attribute::Attribute,comm_delay::Float64,schedule_delay::Float64) = Channel(StateManager(),from_attribute,to_attribute,comm_delay,schedule_delay,0,nothing)

##########################
# Communication Edges
#########################
#An edge that communicates attributes between nodes
struct CommunicationEdge <: AbstractCommunicationEdge
    baseedge::BasePlasmoEdge    #using the Plasmo interface, a communication edge has all the usual edge functions
    channels::Vector{Channel}   #this could also be accomplished with a multi-graph
    #state_manager::StateManager  #Will use when I code a MultiGraph
end

function CommunicationEdge()
    baseedge = BasePlasmoEdge()
    channels = Channel[]
    return CommunicationEdge(baseedge,channels)
end
PlasmoGraphBase.create_edge(graph::Workflow) = CommunicationEdge()   #PlasmoGraphBase edge construction

getchannels(edge::AbstractCommunicationEdge) = edge.channels
getdelay(edge::AbstractCommunicationEdge,channel::Int) = edge.channels[channel].delay
getdelay(channel::Channel) = channel.delay
isactive(channel::Channel) = channel.state_manager.state == State(:active)
getsignals(channel::Channel) = getsignals(channel.state_manager)
getinitialsignal(channel::AbstractChannel) = getinitialsignal(channel.state_manager)
setinitialsignal(channel::AbstractChannel,signal::AbstractSignal) = setinitialsignal(channel.state_manager,signal)
setinitialsignal(channel::AbstractChannel,signal::Symbol) = setinitialsignal(channel.state_manager,Signal(signal))
getstatemanager(channel::AbstractChannel) = channel.state_manager

getstates(channel::AbstractChannel) = getstates(channel.state_manager)
gettransitions(channel::AbstractChannel) = gettransitions(channel.state_manager)
getcurrentstate(channel::AbstractChannel) = getcurrentstate(channel.state_manager)
getlocaltime(channel::AbstractChannel) = channel.state_manager.local_time

function addchannel!(edge::AbstractCommunicationEdge,from_attribute::Attribute,to_attribute::Attribute;comm_delay = 0,schedule_delay = 0,store_history = true)
    channel = Channel(from_attribute,to_attribute,comm_delay,schedule_delay)
    setstates(channel.state_manager,[:null,:active,:inactive,:error])
    setstate(channel.state_manager,:active)
    push!(edge.channels,channel)
    store_history == true && (channel.history = Vector{Tuple}())
    return channel
end

setdelay(edge::AbstractCommunicationEdge,channel::Int,delay::Float64) = edge.channels[channel].delay = delay

#dispatch edge communicates when it receives attribute updates
function add_dispatch_edge!(workflow::Workflow,attribute1::Attribute,attribute2::Attribute;send_attribute_updates = true, comm_delay = 0,continuous = false, schedule_delay = 0,start_time = 0)
    edge = add_edge!(workflow,getnode(attribute1),getnode(attribute2))
    channel = addchannel!(edge,attribute1,attribute2,comm_delay = Float64(comm_delay),schedule_delay = Float64(schedule_delay))

    destination_node = getnode(attribute2)
    suppresssignal!(destination_node.state_manager,Signal(:comm_sent,attribute1))

    if send_attribute_updates == true
        addtransition!(channel.state_manager,State(:active), Signal(:attribute_updated,attribute1), State(:active),action = TransitionAction(communicate,[workflow,channel]), targets = [destination_node.state_manager])
    end

    if continuous == true
        addtransition!(channel.state_manager,State(:active), Signal(:comm_sent,attribute1), State(:active), action = TransitionAction(schedule_communicate,[workflow,channel]),targets = [channel.state_manager])
        schedulesignal(workflow,Signal(:communicate),channel,start_time)
        suppresssignal!(channel.state_manager,Signal(:comm_received,attribute2))
    end

    #run communication when given :communicate signal
    addtransition!(channel.state_manager,State(:active), Signal(:communicate), State(:active), action = TransitionAction(communicate,[channel]), targets = [channel.state_manager,destination_node.state_manager])

    return channel
end

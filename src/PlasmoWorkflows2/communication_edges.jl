mutable struct Channel <: AbstractChannel
    state_manager::StateManager
    from_attribute::Attribute
    to_attribute::Attribute
    delay::Float64           #communication delay
    schedule_delay::Float64
    priority::Int            #signal priority (might make this event specific)
    #poll_time::Float64      # set frequency
end
Channel(from_attribute::Attribute,to_attribute::Attribute) = Channel(StateManager(),from_attribute,to_attribute,0.0,0)
Channel(from_attribute::Attribute,to_attribute::Attribute,delay::Float64) = Channel(StateManager(),from_attribute,to_attribute,0.0,0)

##########################
# Communication Edges
#########################
#An edge that communicates attributes between nodes
struct CommunicationEdge <: AbstractCommunicationEdge
    baseedge::BasePlasmoEdge    #using the Plasmo interface, a communication edge has all the usual edge functions
    channels::Vector{Channel}   #this could also be accomplished with a multi-graph
    #state_manager::StateManager
end

function CommunicationEdge()
    baseedge = BasePlasmoEdge()
    channels = Channel[] #[Channel()]
    #state_manager = StateManager()
    return CommunicationEdge(baseedge,channels,state_manager)
end
create_edge(graph::Workflow) = CommunicationEdge()   #PlasmoGraphBase edge construction

# getdelay(edge::AbstractCommunicationEdge,channel::Int) = edge.channels[channel].delay
# isactive(edge::AbstractCommunicationEdge) = edge.state == State(:active)

#getsignals(edge::AbstractCommunicationEdge) = getsignals(edge.state_manager)
getdelay(edge::AbstractCommunicationEdge,channel::Int) = edge.channels[channel].delay
getdelay(channel::Channel) = channel.delay
isactive(channel::Channel) = channel.state_manager.state == State(:active)
getsignals(channel::Channel) = getsignals(channel.state_manager)

function addchannel!(edge::AbstractCommunicationEdge,from_attribute::Attribute,to_attribute::Attribute;delay = 0)
    push!(edge.channels,Channel(from_attribute,to_attribute,delay))
end

setdelay(edge::AbstractCommunicationEdge,channel::Int,delay::Float64) = edge.channels[channel].delay = delay

#dispatch edge communicates when it receives attribute updates
function add_dispatch_edge!(workflow::Workflow,attribute1::Attribute,attribute2::Attribute;delay = 0.0)
    edge = add_edge!(workflow,getnode(attribute1),getnode(attribute2))
    channel = add_channel!(edge,attribute1,attribute2,delay)
    state_manager = channel.state_manager
    #run communication when attribute updates
    addtransition!(state_manager,State(:active), Signal(:attribute_updated), State(:active), action = TransitionAction(communicate,workflow,edge), targets = [edge.state_manager])
    #run communication when given :communicate signal
    addtransition!(state_manager,State(:active), Signal(:communicate), State(:active), action = TransitionAction(communicate,workflow,edge), targets = [edge.state_manager])

    return channel
end

function add_continuous_edge!(workflow::Workflow,attribute1::Attribute,attribute2::Attribute;delay = 0.0)
    edge = add_edge!(workflow,getnode(attribute1),getnode(attribute2))
    channel = add_channel!(edge,attribute1,attribute2,delay)
    state_manager = channel.state_manager
    #run communication at a frequency
    addtransition!(state_manager,State(:active), Signal(:comm_sent), State(:active), action = TransitionAction(schedule_communicate,workflow,edge),targets = [edge.state_manager])
    #run communication when given :communicate signal
    addtransition!(state_manager,State(:active), Signal(:communicate), State(:active), action = TransitionAction(communicate,workflow,edge),targets = [edge.state_manager])

    return channel
end

#set_trigger_frequency(edge::AbstractCommunicationEdge,frequency::Number) = edge.frequency = Float64(frequency)

# getchannelfrom(edge::AbstractCommunicationEdge) = getconnectfrom(edge).output.edge_map[edge]
# getchannelto(edge::AbstractCommunicationEdge) = getconnectto(edge).input.edge_map[edge]

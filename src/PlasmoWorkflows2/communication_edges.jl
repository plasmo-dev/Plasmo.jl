mutable struct Channel
    from_attribute::Attribute
    to_attribute::Attribute
    delay::Float64          # communication delay
    priority::Int
    #poll_time::Float64      # set frequency
end
Channel() = Channel(Attribute(),Attribute(),0,0)
Channel(from_attribute::Attribute,to_attribute::Attribute) = Channel(from_attribute,to_attribute,0,0)
getdelay(channel::Channel) = channel.delay

##########################
# Communication Edges
#########################
#An edge that simply communicates a result when a dispatch node completes
struct CommunicationEdge <: AbstractCommunicationEdge
    baseedge::BasePlasmoEdge   #using the Plasmo interface, a communication edge has all the usual edge functions
    channels::Vector{Channel}
    state_manager::StateManager
end

function CommunicationEdge()
    baseedge = BasePlasmoEdge()
    channels = [Channel()]
    state_manager = StateManager()
    return CommunicationEdge(baseedge,channels,state_manager)
end
create_edge(graph::Workflow) = CommunicationEdge()   #PlasmoGraphBase edge construction


getdelay(edge::AbstractCommunicationEdge,channel::Int) = edge.channels[channel].delay
isactive(edge::AbstractCommunicationEdge) = edge.state == State(:active)

getsignals(edge::AbstractCommunicationEdge) = getsignals(edge.state_manager)

setdelay(edge::AbstractCommunicationEdge,channel::Int,delay::Float64) = edge.channels[channel].delay = delay
set_trigger_frequency(edge::AbstractCommunicationEdge,frequency::Number) = edge.frequency = Float64(frequency)

# getchannelfrom(edge::AbstractCommunicationEdge) = getconnectfrom(edge).output.edge_map[edge]
# getchannelto(edge::AbstractCommunicationEdge) = getconnectto(edge).input.edge_map[edge]

struct Channel
    from_attribute::Attribute
    to_attribute::Attribute
    delay::Float64          # communication delay
    #poll_time::Float64      # set frequency
end
Channel() = Channel(Attribute(),Attribute(),0)
Channel(from_attribute::Attribute,to_attribute::Attribute) = Channel(from_attribute,to_attribute,0,0)
getdelay(channel::Channel) = channel.delay

##########################
# Communication Edges
#########################
#An edge that simply communicates a result when a dispatch node completes
struct CommunicationEdge <: AbstractCommunicationEdge
    baseedge::BasePlasmoEdge   #using the Plasmo interface, a communication edge has all the usual edge functions
    priority::Int
    channels::Vector{Channel}
    state_manager::StateManager
end

function CommunicationEdge()
    baseedge = BasePlasmoEdge()
    priority = 0
    channels = [Channel()]
    state_manager = StateManager()
    return CommunicationEdge(baseedge,priority,channels,state_manager)
end
create_edge(graph::Workflow) = CommunicationEdge()   #PlasmoGraphBase edge construction


getdelay(edge::AbstractCommunicationEdge) = edge.delay
isactive(edge::AbstractCommunicationEdge) = edge.active
gettriggers(edge::AbstractCommunicationEdge) = edge.triggers
setdelay(edge::AbstractCommunicationEdge,delay::Number) = edge.delay = Float64(delay)
set_trigger_frequency(edge::AbstractCommunicationEdge,frequency::Number) = edge.frequency = Float64(frequency)

getchannelfrom(edge::AbstractCommunicationEdge) = getconnectfrom(edge).output.edge_map[edge]
getchannelto(edge::AbstractCommunicationEdge) = getconnectto(edge).input.edge_map[edge]

# #Trigger an edge with an event
# function send_trigger!(workflow::Workflow,event::AbstractEvent,edge::CommunicationEdge)
#     if typeof(event) in gettriggers(edge)
#         trigger!(workflow,edge,getcurrenttime(workflow))
#     end
# end
#
# #Trigger an edge with an event
# function send_trigger!(workflow::Workflow,event::AbstractEvent,edge::CommunicationEdge,time::Number)
#     if typeof(event) in gettriggers(edge)
#         trigger!(workflow,edge,time)
#     end
# end

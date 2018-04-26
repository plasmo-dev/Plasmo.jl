##########################
# Communication Edges
#########################
#An edge that simply communicates a result when a dispatch node completes
mutable struct CommunicationEdge <: AbstractCommunicationEdge
    baseedge::BasePlasmoEdge   #using the Plasmo interface, a communication edge has all the usual edge functions
    priority::Int
    #local_time::Float64
    delay::Float64  #delay transfer of information  #use a sleep?
    frequency::Float64

    enter::ConditionFunction                    #function to clean inputs to pass into func.  Can also be used as a condition check.  If no prepare, the input just goes into the args.
    exit::ConditionFunction                     #do any cleanup, trigger other events


    #communication_frequency::Float64  #might get rid of this
    active::Bool  #active or inactive
    triggers::Vector{DataType}
end

addtrigger!(edge::CommunicationEdge,event::DataType) = push!(edge.triggers,event)
settrigger(edge::CommunicationEdge,event::DataType) = edge.triggers = [event]

CommunicationEdge() = CommunicationEdge(BasePlasmoEdge(),0,0.0,0.0,ConditionFunction(),ConditionFunction(),true,[NodeCompleteEvent])

create_edge(graph::Workflow) = CommunicationEdge()   #PlasmoGraphBase edge construction

#add edge for a workflow should set default port channels?
# function add_edge!(workflow::Workflow,node1::AbstractDispatchNode,node2::AbstractDispatchNode)
#     edge = PlasmoGraphBase.add_edge!(workflow,node1,node2)
#     return edge
# end


getdelay(edge::AbstractCommunicationEdge) = edge.delay
isactive(edge::AbstractCommunicationEdge) = edge.active
gettriggers(edge::AbstractCommunicationEdge) = edge.triggers
setdelay(edge::AbstractCommunicationEdge,delay::Number) = edge.delay = Float64(delay)
set_trigger_frequency(edge::AbstractCommunicationEdge,frequency::Number) = edge.frequency = Float64(frequency)

getchannelfrom(edge::AbstractCommunicationEdge) = getconnectfrom(edge).output.edge_map[edge]
getchannelto(edge::AbstractCommunicationEdge) = getconnectto(edge).input.edge_map[edge]

#Trigger an edge with an event
function send_trigger!(workflow::Workflow,event::AbstractEvent,edge::CommunicationEdge)
    if typeof(event) in gettriggers(edge)
        trigger!(workflow,edge,getcurrenttime(workflow))
    end
end

#Trigger an edge with an event
function send_trigger!(workflow::Workflow,event::AbstractEvent,edge::CommunicationEdge,time::Number)
    if typeof(event) in gettriggers(edge)
        trigger!(workflow,edge,time)
    end
end

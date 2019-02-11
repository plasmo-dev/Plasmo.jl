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
    local_time::Float64
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
    edge.local_time = 0.0
    edge.history = Vector{Tuple}()
    return edge
end
PlasmoGraphBase.create_edge(graph::ComputingGraph) = CommunicationEdge()   #PlasmoGraphBase edge construction

#getchannels(edge::AbstractCommunicationEdge) = edge.channels
getdelay(edge::AbstractCommunicationEdge) = edge.delay
getlocaltime(edge::AbstractCommunicationEdge) = edge.local_time
getstate(edge::AbstractCommunicationEdge) = getstate(edge.state_manager)
iscommunicating(edge::CommunicationEdge) = getstate(edge) == state_communicating()
getvalidsignals(edge::CommunicationEdge) = getvalidsignals(edge.state_manager)
getstatemanager(edge::AbstractCommunicationEdge) = edge.state_manager

getvalidstates(edge::AbstractCommunicationEdge) = getvalidstates(edge.state_manager)
gettransitions(edge::AbstractCommunicationEdge) = gettransitions(edge.state_manager)
#getcurrentstate(edge::AbstractCommunicationEdge) = getcurrentstate(edge.state_manager)

setdelay(edge::AbstractCommunicationEdge,delay::Float64) = edge.delay = delay

#dispatch edge communicates when it receives attribute updates
function addedge!(graph::AbstractComputingGraph,attribute1::NodeAttribute,attribute2::NodeAttribute;
    delay::Number = 0,send_on::Vector{Signal} = Signal[],send_delay::Number = 0.0)

    delay = Float64(delay)

    edge = add_edge!(graph,getnode(attribute1),getnode(attribute2))
    edge.from_attribute = attribute1
    edge.to_attribute = attribute2
    edge.send_triggers = send_on
    edge.delay = delay

    push!(attribute1.out_edges,edge)
    push!(attribute2.in_edges,edge)

    #Notify attribute that it triggers this edge
    for signal in send_on
        label = signal.label
        attribute = signal.value
        attribute.triggers[label] = edge
    end

    #communication actions
    addtransition!(edge,state_idle(), signal_communicate(), state_communicating();action = action_communicate())
    addtransition!(edge,state_communicating(),signal_communicate(),state_communicating())

    #NOTE: Need to add schedule_communicate signal
    # addtransition!(edge,state_idle(),signal_schedule_communicate(),state_communicating(),action = action_schedule_communicate(send_delay))
    # addtransition!(edge,state_communicating(),signal,state_communicating(),action = action_schedule_communicate(send_delay))

    #schedule communication actions
    for signal in edge.send_triggers
        addtransition!(edge,state_idle(),signal,state_communicating(),action = action_schedule_communicate(send_delay))
        addtransition!(edge,state_communicating(),signal,state_communicating(),action = action_schedule_communicate(send_delay))
    end

    return edge
end

const connect! = addedge!

function addcomputeattribute!(edge::CommunicationEdge,label::Symbol,value::Any)#; update_notify_targets = SignalTarget[])   #,execute_on_receive = true)
    attribute = EdgeAttribute(edge,label,value)
    push!(edge.attribute_pipeline,attribute)
    return attribute
end

function removecomputeattribute!(edge::CommunicationEdge,attribute::EdgeAttribute)
    filter!(x->x != attribute,edge.attribute_pipeline)
end

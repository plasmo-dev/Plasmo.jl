##########################
# Dispatch Result
##########################
#A node's current dispatch result.  This might end up as anything.
# struct NodeDispatchResult
#     result::Nullable{Any}               #A Future or Task?  Look at DeferredFutures
#     slots::Vector{Any}                  #result goes into first slot automatically
# end

#NodeDispatchResult() = NodeDispatchResult(Nullable{Any}(),Vector{Any}())
#getresult(res::NodeDispatchResult) = get(res.result)
#getresultslots(res::NodeDispatchResult) = res.slots

#A discrete node gets scheduled on edge triggering
mutable struct DispatchNode <: AbstractDispatchNode  #A Dispatch node
    basenode::BasePlasmoNode

    node_data::Dict{Symbol,Any}                 #node attribute data
    input::Input                                #node input data
    output::Output                              #node output data
    active::Bool                                #active or inactive (i.e. deleted)

    priority::Int

    local_time::Float64                         #The node's local clock.  Gets synchronized with the workflow clock on triggers
    compute_time::Float64                       #The time the node takes to complete its task.

    #These are for adding customization.  Most use-cases shouldn't need to mess with the enter and exit behavior
    enter::ConditionFunction                    #function to clean inputs to pass into func.  Can also be used as a condition check.  If no prepare, the input just goes into the args.
    exit::ConditionFunction                     #do any cleanup, trigger other events

    dispatch_function::DispatchFunction         #the actual function to call
    #result::NodeDispatchResult                 #::DeferredFuture #need to figure out how these work
    result_map::Vector{Pair}                #Result_slot => channel_id

    triggers::Vector{DataType}                  #events that can trigger this dispatch node
end
DispatchNode() = DispatchNode(BasePlasmoNode(),Dict{Any,Any}(),Input(),Output(),true,0,0.0,0.0,ConditionFunction(),ConditionFunction(),DispatchFunction(),[Pair(1,1)],
                                [CommunicationReceivedEvent])
create_node(graph::Workflow) = DispatchNode()

function add_dispatch_node!(workflow::Workflow;input_channels = (),output_channels = ())
    node = add_node!(workflow)

    if !isa(input_channels,Tuple)
        input_channels = tuple(input_channels)
    end
    if !isa(output_channels,Tuple)
        output_channels = tuple(output_channels)
    end

    #Add the channel labels
    for (i,label) in enumerate(input_channels)
        node.input.channel_labels[label] = i
    end

    for (i,label) in enumerate(output_channels)
        node.output.channel_labels[label] = i
    end
    return node
end


###########################
# Node Triggers
###########################
gettriggers(node::DispatchNode) = node.triggers
addtrigger!(node::DispatchNode,event::DataType) = push!(node.triggers,event)
settrigger(node::DispatchNode,event::DataType) = node.triggers = [event]

#Trigger (schedule) by responding to an event that sends it a trigger
function send_trigger!(workflow::Workflow,event::AbstractEvent,node::DispatchNode)
    if typeof(event) in gettriggers(node)
        trigger!(workflow,node,getcurrenttime(workflow))
    end
end

getlocaltime(node::AbstractDispatchNode) = node.local_time
##########################
#Node Result
##########################
getresult(node::AbstractDispatchNode) = getresult(node.dispatch_function)

##########################
#Node Channels
##########################
#Get input and output ports
getinput(node::AbstractDispatchNode) = node.input
getinput(node::AbstractDispatchNode,label::Symbol) = node.input.channel_data[node.input.channel_labels[label]]
getoutput(node::AbstractDispatchNode) = node.output

#Get input and output data
getnodeinputdata(node::AbstractDispatchNode) = getportdata(node.input)
getnodeoutputdata(node::AbstractDispatchNode) = getportdata(node.output)

#Get input and output data channels
getchanneldata_in(node::AbstractDispatchNode,i::Int) = getchanneldata(node.input,i)
getchanneldata_in(node::AbstractDispatchNode,s::Symbol) = getchanneldata(node.input,s)
getchanneldata_out(node::AbstractDispatchNode,i::Int) = getchanneldata(node.output,i)
getchanneldata_out(node::AbstractDispatchNode,s::Symbol) = getchanneldata(node.output,s)

#Set all channel inputs to the given data.  Useful for initializing.
setchanneldata_in(workflow::Workflow,node::AbstractDispatchNode,data) = node.input.data = Dict(zip(in_edges(workflow,node),[data for i = 1:in_degree(workflow,node)]))
setchanneldata_in(workflow::Workflow,node::AbstractDispatchNode,channel_id::Int,data) = node.input.data[node.input.edge_map[channel_id]] = data

#TODO Clean this tup
function setinputs(node::AbstractDispatchNode;kwargs...)
    input = getinput(node)
    #if the labels don't exist, create them
    for pair in kwargs
        label = pair[1]
        value = pair[2]
        #Create a new channel if needed
        if !(label in keys(input.channel_labels))
            input.channel_labels[label] = length(input.channel_labels) + 1
        end
        channel = input.channel_labels[label]
        input.channel_data[channel] = value
    end
end



##########################
#Node Dispatch Function
##########################
set_node_function(node::AbstractDispatchNode,func::Function) = node.dispatch_function = DispatchFunction(func)
set_node_function_arguments(node::AbstractDispatchNode,args::Vector{Any}) = node.dispatch_function.args = args
set_node_function_arguments(node::AbstractDispatchNode,arg::Any) = node.dispatch_function.args = [arg]
set_node_function_kwargs(node::AbstractDispatchNode,kwargs::Dict{Any,Any}) = node.dispatch_function.kwargs = kwargs

set_node_compute_time(node::AbstractDispatchNode,time::Float64) = node.compute_time = time

set_result_to_output_channel(node::AbstractDispatchNode,i::Int) = node.output.channels[i] = getresult(node)
set_result_to_output_channel(node::AbstractDispatchNode,s::Symbol) = node.output.channel_labels[s] = getresult(node)

function set_result_slot_to_output_channel!(node::AbstractDispatchNode,result_slot::Int,channel::Int)
    output = node.output
    @assert channel in output.channels
    pair = Pair(result_slot,channel)
    if !(pair in node.result_map)
        push!(node.result_map,pair)
    end
    #node.result_map[result_slot] = channel
end

#Set a result slot to a channel label (and hence id)
function set_result_slot_to_output_channel!(node::AbstractDispatchNode,result_slot::Int,channel::Symbol)
    output = node.output
    @assert channel in keys(output.channel_labels)
    pair = Pair(result_slot,output.channel_labels[channel])
    if !(pair in node.result_map)
        push!(node.result_map,pair)
    end
    #node.result_map[result_slot] = output.channel_labels[channel]
end

########################################
#Update Node Inputs and Outputs
########################################
#update node output using result slot information on the node
function update_node_output(workflow::Workflow,node::DispatchNode)  #,edge::CommunicationEdge)
    result = [getresult(node)]            #Get the node result from the dispatch function
    res_map = node.result_map           #{result_slot => channel_id}
    output = getoutput(node)            #the node output port
    for (slot,channel) in res_map
        #NOTE No edge map if no edges.  Outputs shouldn't require there to be edges
        #output.data[output.edge_map[channel]] = result[slot]     #might need workflow argument if managing multiple workflows with the same nodes
        #output.data[channel] = result[slot]
        setportdata(output,channel,result[slot])
    end
end

#Update node input port using input edge data
function update_node_input(workflow::Workflow,edge::CommunicationEdge,input_data)
    node = getconnectedto(workflow,edge)
    input = getinput(node)
    channel = getchannel(node.input,edge)
    setportdata(input,channel,input_data)
end

########################################
#Connect Nodes with Communication Edges
########################################
function connect!(workflow::Workflow,dnode1::DispatchNode,dnode2::DispatchNode;input_channel = 0,output_channel = 0,delay = 0,communication_frequency = 0)
    #is_connected(workflow,dnode1,dnode2) && throw("communication edge already exists between these nodes")

    #use the first channel on the input port if it's not specified
    if input_channel == 0
        input_channel = 1
    end
    #use the first channel on the output port if it's not specified
    if output_channel == 0
        output_channel = 1
    end

    if isa(input_channel,Symbol)
        input_channel = dnode2.input.channel_labels[input_channel]
    end

    if isa(output_channel,Symbol)
        output_channel = dnode1.output.channel_labels[output_channel]
    end

    #Default connection behavior
    comm_edge = add_edge!(workflow,dnode1,dnode2)
    setdelay(comm_edge,delay)
    if communication_frequency > 0
        set_trigger_frequency(comm_edge,communication_frequency)
        settrigger(comm_edge,EdgeTriggerEvent)
    end

    set_channel_to_edge!(dnode1.output,comm_edge,output_channel)
    set_channel_to_edge!(dnode2.input,comm_edge,input_channel)

    return comm_edge
end

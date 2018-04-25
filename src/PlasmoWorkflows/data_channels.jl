#Abstract Port for both Input and Output data
abstract type AbstractDataPort end

################################
# Input Data Port
################################
mutable struct Input <: AbstractDataPort
    channel_data::Dict{Int,Any}                             #each channel map to some data.  By default, there is no data
    channel_labels::Dict{Symbol,Int}                        #channels might not have labels
    edge_map::Dict{AbstractCommunicationEdge,Int}           #channel map to the edges
    channel_map::Dict{Int,AbstractCommunicationEdge}
end
#Constructor (default: 1 channel)
Input() = Input(Dict{Int,Any}(1 => nothing),Dict{Symbol,Int}(),Dict{AbstractCommunicationEdge,Int}(),Dict{Int,AbstractCommunicationEdge}())

###############################
# Output Data Port
###############################
mutable struct Output <: AbstractDataPort
    channel_data::Dict{Int,Any}                             #each channel map to some data.  By default, there is no data
    channel_labels::Dict{Symbol,Int}                        #channels might not have labels
    edge_map::Dict{AbstractCommunicationEdge,Int}           #channel map to the edges
    channel_map::Dict{Int,AbstractCommunicationEdge}
end
Output() = Output(Dict{Int,Any}(1 => nothing),Dict{Symbol,Int}(),Dict{AbstractCommunicationEdge,Int}(),Dict{Int,AbstractCommunicationEdge}())

getportdata(port::AbstractDataPort) = port.channel_data                         #Get data associated with a port, returns dictionary
getportdata(port::AbstractDataPort,channel::Int) = port.channel_data[channel]
getnumchannels(port::AbstractDataPort) = length(port.channel_data)
setportdata(port::AbstractDataPort,channel::Int,data::Any) = port.channel_data[channel] = data
getchannel(port::AbstractDataPort,edge::AbstractCommunicationEdge) = port.edge_map[edge]

#add a channel to a port(without a label)
function add_port_channel!(port::AbstractDataPort)
    n_channels = getnumchannels(port)
    port.channel_data[n_channels + 1] = nothing
end

#map a communication edge to a channel
function set_channel_to_edge!(port::AbstractDataPort,edge::AbstractCommunicationEdge,channel_id::Int)
    #@assert channel_id in keys(port.channel_data)
    port.edge_map[edge] = channel_id
    port.channel_map[channel_id] = edge
end

#set a channel label
function set_channel_label!(port::AbstractDataPort,channel_id::Int,channel_label::Symbol)
    @assert channel_id in keys(port.channel_labels)
    port.channel_labels[channel_label] = channel_id
end

getchanneldata(port::AbstractDataPort,channel_id::Int) = port.channel_data[channel_id]
getchanneldata(port::AbstractDataPort,label::Symbol) = port.channel_data[channel_labels[label]]


#get the data communicated to a channel using the channel id
# function getchanneldata(port::AbstractDataPort,channel_id::Int)
#     #edge = port.edge_map[channel_id]
#     return port.channel_data[channel_id]
#     #return data[edge]
# end
#
# #get the data communicated to a channel using the channel label
# function getchanneldata(port::AbstractDataPort,label::Symbol)
#     return port.channel_data[channel_labels[label]]
#     #edge = port.edge_map[channel_labels[channel_label]]
#     #return data[edge]
# end

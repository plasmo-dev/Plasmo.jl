#A workflow node attribute.  Has local and global values to manage clock timings
mutable struct NodeAttribute <: AbstractAttribute
    node::AbstractComputeNode
    label::Symbol
    local_value::Any    #local to the node
    global_value::Any   #updated globally
    out_edges::Vector{AbstractCommunicationEdge}
    in_edges::Vector{AbstractCommunicationEdge}

    #Signals corresponding to an attribute can trigger tasks or edge communication
    signal_triggers::Dict{Symbol,Vector{Union{NodeTask,AbstractCommunicationEdge}}}

    function NodeAttribute(node::AbstractComputeNode,label::Symbol,value::Any)
        attribute = new()
        attribute.node = node
        attribute.label = label
        attribute.local_value = value
        attribute.global_value = value
        attribute.out_edges = Vector{AbstractCommunicationEdge}()
        attribute.in_edges = Vector{AbstractCommunicationEdge}()

        attribute.signal_triggers = Dict{Symbol,Vector{Union{NodeTask,AbstractCommunicationEdge}}}()
        attribute.signal_triggers[:updated] = Vector{Union{NodeTask,AbstractCommunicationEdge}}()
        attribute.signal_triggers[:sent] = Vector{Union{NodeTask,AbstractCommunicationEdge}}()
        attribute.signal_triggers[:received] = Vector{Union{NodeTask,AbstractCommunicationEdge}}()

        return attribute
    end
end
NodeAttribute(node::AbstractComputeNode) = NodeAttribute(node,gensym(),nothing)
NodeAttribute(node::AbstractComputeNode,label::Symbol) = NodeAttribute(node,label,nothing)

# ==(attribute1::Attribute,attribute2::Attribute) = (attribute1.node == attribute2.node && attribute1.label == attribute2.label)
#Attribute(node::AbstractComputeNode,object::Any) = Attribute(node,gensym(),object,object)

getnode(attribute::NodeAttribute) = attribute.node
getlabel(attribute::NodeAttribute) = attribute.label
getlocalvalue(attribute::NodeAttribute) = attribute.local_value
getglobalvalue(attribute::NodeAttribute) = attribute.global_value
getvalue(attribute::NodeAttribute) = getlocalvalue(attribute)

#Update attribute values
function setvalue(attribute::NodeAttribute,value::Any)
    attribute.local_value = value
    node = getnode(attribute)
    if !(attribute in node.local_attributes_updated)
        push!(node.local_attributes_updated,attribute)
    end
    return attribute
end

function finalizevalue(attribute::NodeAttribute)
    attribute.global_value = attribute.local_value
end

isoutconnected(attribute::NodeAttribute) = length(attribute.out_channels) > 0
isinconnected(attribute::NodeAttribute) = length(attribute.in_channels) > 0

isupdatetrigger(attribute::NodeAttribute) = length(attribute.signal_triggers[:updated]) > 0
issendtrigger(attribute::NodeAttribute) = length(attribute.signal_triggers[:sent]) > 0
isreceivetrigger(attribute::NodeAttribute) = length(attribute.signal_triggers[:received]) > 0

updatetargets(attribute::NodeAttribute) = attribute.signal_triggers[:updated]
sendtargets(attribute::NodeAttribute) = attribute.signal_triggers[:sent]
receivetargets(attribute::NodeAttribute) = attribute.signal_triggers[:received]
#A workflow node attribute.  Has local and global values to manage time synchronization
mutable struct EdgeAttribute <: AbstractAttribute
    edge::AbstractCommunicationEdge
    label::Symbol
    value::Any
end
EdgeAttribute(edge::AbstractCommunicationEdge,value::Any) = EdgeAttribute(edge,gensym(),value)
#EdgeAttribute(edge::AbstractCommunicationEdge,label::Symbol,value::Any) = EdgeAttribute(edge,label,value)

getvalue(attribute::EdgeAttribute) = attribute.value

function string(attribute::AbstractAttribute)
    string(attribute.label)
end
print(io::IO, attribute::AbstractAttribute) = print(io, string(attribute))
show(io::IO, attribute::AbstractAttribute) = print(io,attribute)

# isupdatetrigger(attribute::NodeAttribute) = length(attribute.update_triggers) > 0
# issendtrigger(attribute::NodeAttribute) = length(attribute.send_triggers) > 0
# isreceivetrigger(attribute::NodeAttribute) = length(attribute.receive_triggers) > 0

# update_triggers::Vector{Union{NodeTask,AbstractCommunicationEdge}}    #attribute updates can trigger tasks or communication
# send_triggers::Vector{Union{NodeTask,AbstractCommunicationEdge}}      #attribute sent can trigger tasks or communication
# receive_triggers::Vector{Union{NodeTask,AbstractCommunicationEdge}}   #attribute received can trigger tasks or communication

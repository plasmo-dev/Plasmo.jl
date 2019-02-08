#A workflow node attribute.  Has local and global values to manage time synchronization
mutable struct NodeAttribute <: AbstractAttribute
    node::AbstractComputeNode
    label::Symbol
    local_value::Any    #local to the node
    global_value::Any   #updated globally
    out_edges::Vector{AbstractCommunicationEdge}
    in_edges::Vector{AbstractCommunicationEdge}
    # update_triggers::Vector{NodeTask}    #attribute updates can trigger tasks
    # send_triggers::Vector{NodeTask}      #attribute sent can trigger tasks
    # receive_triggers::Vector{NodeTask}   #attribute received can trigger tasks
end
NodeAttribute(node::AbstractComputeNode) = NodeAttribute(node,gensym(),nothing,nothing,Vector{AbstractCommunicationEdge}(),Vector{AbstractCommunicationEdge}())
NodeAttribute(node::AbstractComputeNode,label::Symbol) = Attribute(node,label,nothing,nothing,Vector{AbstractCommunicationEdge}(),Vector{AbstractCommunicationEdge}())
NodeAttribute(node::AbstractComputeNode,label::Symbol,value::Any) = Attribute(node,label,value,value,Vector{AbstractCommunicationEdge}(),Vector{AbstractCommunicationEdge}())

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
        push!(node.updated_attributes,attribute)
    end
end

function finalizevalue(attribute::NodeAttribute)
    attribute.global_value = attribute.local_value
end

isoutconnected(attribute::NodeAttribute) = length(attribute.out_channels) > 0
isinconnected(attribute::NodeAttribute) = length(attribute.in_channels) > 0
isupdatetrigger(attribute::NodeAttribute) = length(attribute.update_triggers) > 0
issendtrigger(attribute::NodeAttribute) = length(attribute.send_triggers) > 0
isreceivetrigger(attribute::NodeAttribute) = length(attribute.receive_triggers) > 0

#A workflow node attribute.  Has local and global values to manage time synchronization
mutable struct EdgeAttribute <: AbstractAttribute
    edge::AbstractCommunicationEdge
    label::Symbol
    value::Any
end
EdgeAttribute(edge::AbstractCommunicationEdge) = EdgeAttribute(edge,)
EdgeAttribute(edge::AbstractCommunicationEdge,label::Symbol) = EdgeAttribute(edge,label,nothing)
EdgeAttribute(edge::AbstractCommunicationEdge,label::Symbol,value::Any) = EdgeAttribute(edge,label,value)


function string(attribute::AbstractAttribute)
    string(attribute.label)
end
print(io::IO, attribute::Attribute) = print(io, string(attribute))
show(io::IO, attribute::Attribute) = print(io,attribute)

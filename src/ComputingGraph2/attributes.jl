#A workflow node attribute.  Has local and global values to manage time synchronization
mutable struct NodeAttribute <: AbstractAttribute
    node::AbstractDispatchNode
    label::Symbol
    local_value::Any    #local to the node
    global_value::Any   #updated globally
    out_edges::Vector{AbstractCommunicationEdge}
    in_edges::Vector{AbstractCommunicationEdge}
end
NodeAttribute(node::AbstractDispatchNode) = Attribute(node,gensym(),nothing,nothing,Vector{AbstractChannel}(),Vector{AbstractChannel}())
NodeAttribute(node::AbstractDispatchNode,label::Symbol) = Attribute(node,label,nothing,nothing,Vector{AbstractChannel}(),Vector{AbstractChannel}())
NodeAttribute(node::AbstractDispatchNode,label::Symbol,object::Any) = Attribute(node,label,object,object,Vector{AbstractChannel}(),Vector{AbstractChannel}())

# ==(attribute1::Attribute,attribute2::Attribute) = (attribute1.node == attribute2.node && attribute1.label == attribute2.label)
#Attribute(node::AbstractDispatchNode,object::Any) = Attribute(node,gensym(),object,object)

getnode(attribute::Attribute) = attribute.node
getlabel(attribute::Attribute) = attribute.label
getlocalvalue(attribute::Attribute) = attribute.local_value
getglobalvalue(attribute::Attribute) = attribute.global_value
getvalue(attribute::Attribute) = getlocalvalue(attribute)

function updateattribute(attribute::Attribute,value::Any)
    attribute.local_value = value
    push!(attribute.node.updated_attributes,attribute)
end

isoutconnected(attribute::Attribute) = length(attribute.out_channels) > 0
isinconnected(attribute::Attribute) = length(attribute.in_channels) > 0


#A workflow node attribute.  Has local and global values to manage time synchronization
mutable struct EdgeAttribute <: AbstractAttribute
    edge::AbstractCommunicationEdge
    label::Symbol
    value::Any
end
Attribute(node::AbstractDispatchNode) = Attribute(node,gensym(),nothing,nothing,Vector{AbstractChannel}(),Vector{AbstractChannel}())
Attribute(node::AbstractDispatchNode,label::Symbol) = Attribute(node,label,nothing,nothing,Vector{AbstractChannel}(),Vector{AbstractChannel}())
Attribute(node::AbstractDispatchNode,label::Symbol,object::Any) = Attribute(node,label,object,object,Vector{AbstractChannel}(),Vector{AbstractChannel}())

#A workflow node attribute.  Has local and global values to manage time synchronization
mutable struct EdgeAttribute <: AbstractAttribute
    edge::AbstractCommunicationEdge
    label::Symbol
    value::Any
end
EdgeAttribute(edge::AbstractCommunicationEdge) = Attribute(node,gensym(),nothing,nothing,Vector{AbstractChannel}(),Vector{AbstractChannel}())
EdgeAttribute(node::AbstractDispatchNode,label::Symbol) = Attribute(node,label,nothing,nothing,Vector{AbstractChannel}(),Vector{AbstractChannel}())
EdgeAttribute(node::AbstractDispatchNode,label::Symbol,object::Any) = Attribute(node,label,object,object,Vector{AbstractChannel}(),Vector{AbstractChannel}())



function string(attribute::AbstractAttribute)
    string(attribute.label)
end
print(io::IO, attribute::Attribute) = print(io, string(attribute))
show(io::IO, attribute::Attribute) = print(io,attribute)

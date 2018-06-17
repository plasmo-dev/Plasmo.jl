#A workflow node attribute.  Has local and global values to manage time synchronization
mutable struct Attribute
    node::AbstractDispatchNode
    label::Symbol
    local_value::Any   #local to the node
    global_value::Any
    out_channels::Vector{AbstractChannel}
    in_channels::Vector{AbstractChannel}
end
Attribute(node::AbstractDispatchNode) = Attribute(node,gensym(),nothing,nothing,Vector{AbstractChannel}(),Vector{AbstractChannel}())
Attribute(node::AbstractDispatchNode,label::Symbol) = Attribute(node,label,nothing,nothing,Vector{AbstractChannel}(),Vector{AbstractChannel}())
Attribute(node::AbstractDispatchNode,label::Symbol,object::Any) = Attribute(node,label,object,object,Vector{AbstractChannel}(),Vector{AbstractChannel}())

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

function string(attribute::Attribute)
    string(attribute.label)
end
print(io::IO, attribute::Attribute) = print(io, string(attribute))
show(io::IO, attribute::Attribute) = print(io,attribute)

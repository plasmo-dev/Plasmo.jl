#A workflow node attribute.  Has local and global values to manage time synchronization
mutable struct Attribute
    node::AbstractDispatchNode
    label::Symbol
    local_value::Any
    global_value::Any
end
Attribute(node::AbstractDispatchNode) = Attribute(node,gensym(),nothing,nothing)
Attribute(node::AbstractDispatchNode,object::Any) = Attribute(node,gensym(),object,object)

getnode(attribute::Attribute) = attribute.node
getlabel(attribute::Attribute) = attribute.label
getlocalvalue(attribute::Attribute) = attribute.local_values
getglobalvalue(attribute::Attribute) = attribute.global_value

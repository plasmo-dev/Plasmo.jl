#Functions specifically for associating models with nodes and edges in a plasmo graph

import JuMP:AbstractModel,AbstractConstraint,Variable,ConstraintRef
import MathProgBase

is_nodevar(nodeoredge::NodeOrEdge,var::Variable) = getmodel(nodeoredge) == var.m #checks whether a variable belongs to a node or edge

#Component Models (A node or edge can have a single model)
function setmodel!(nodeoredge::NodeOrEdge,m::AbstractModel)
    #update link constraints after setting a model
    !_assignedtonode(m) || error("the model is already asigned to another node or edge")
    @assert !_assignedtonode(m)  #make sure the model isn't already assigned to a different node
    nodeoredge.attributes[:model] = m
    m.ext[:node] = nodeoredge
    #set variable names
    for i = 1:MathProgBase.numvar(m)
        _setvarname(nodeoredge,Variable(m,i))
    end
end
getnode(m::AbstractModel) = m.ext[:node]
getnode(var::Variable) = var.m.ext[:node]

_assignedtonode(m::AbstractModel) = haskey(m.ext,:node) #check whether a model is assigned to a node
_setvarname(nodeoredge::NodeOrEdge,v::Variable) = JuMP.setname(v,string(nodeoredge.label)*"["*getname(v)*"]") #set a variable name when its model gets assigned to a node or edge

#TODO
#make it possible to reset a model on a node or edge
function resetmodel!(nodeoredge::NodeOrEdge,m::AbstractModel)
    #reassign the model
    #switch out variables in any connected linkconstraints
    #throw warnings if link constraints break
end

#TODO
#removemodel!(nodeoredge::NodeOrEdge) = nodeoredge.attributes[:model] = nothing  #need to update link constraints
getmodel(nodeoredge::NodeOrEdge) = nodeoredge.attributes[:model]
hasmodel(nodeoredge::NodeOrEdge) = haskey(nodeoredge.attributes,:model)
getindex(nodeoredge::NodeOrEdge,s::Symbol) = getmodel(nodeoredge)[s]  #get a node or edge variable

getlinkconstraints(nodeoredge::NodeOrEdge) = nodeoredge.attributes[:LinkData].linkconstraintmap
getlinkconstraints(graph::PlasmoGraph,nodeoredge::NodeOrEdge) = nodeoredge.attributes[:LinkData].linkconstraintmap[graph]
getlinkconstraints(graph::PlasmoGraph) = graph.attributes[:LinkData].linkconstraints

#Add nodes and set the model as well
function add_node!(graph::PlasmoGraph,m::AbstractModel)
    node = add_node!(graph)
    setmodel!(node,m)
    return node
end

#Add edges and set the model as well
function add_edge!(graph::PlasmoGraph,edge::LightGraphs.Edge,m::AbstractModel)
    pedge = add_edge!(graph,edge)
    setmodel!(pedge,m)
    return pedge
end

function add_edge!(graph::PlasmoGraph,pedge::PlasmoEdge,src::PlasmoNode,dst::PlasmoNode,m::AbstractModel)
    pedge = add_edge!(graph,pedge,src,dst)
    setmodel!(pedge,m)
    return pedge
end

#Store link constraint in the given graph.  Store a reference to the linking constraint on the nodes which it links
function _addlinkconstraint!(graph::PlasmoGraph,con::AbstractConstraint)
    vars = con.terms.vars
    #check that all of the variables belong to the same graph
    nodes = unique([getnode(var) for var in vars])
    all(node->node in values(getnodesandedges(graph)),nodes)? nothing: error("the linkconstraint: $con contains variables that don't belong to the graph: $graph")
    push!(graph.attributes[:LinkData].linkconstraints,con)   #add the link constraint to the graph
    for nodeoredge in nodes
        haskey(nodeoredge.attributes[:LinkData].linkconstraintmap,graph)? nothing : nodeoredge.attributes[:LinkData].linkconstraintmap[graph] = Vector{AbstractConstraint}()
        push!(nodeoredge.attributes[:LinkData].linkconstraintmap[graph],con)
    end
end

function _addlinkconstraint!{T}(graph::PlasmoGraph,cons_refs::Array{AbstractConstraint,T})
    array_type = typeof(cons_refs)
    array_type.parameters.length > 1? cons_refs = vec(cons_refs): nothing
    #Check all of the constraints before I add one to the graph
    for con in cons_refs
        vars = con.terms.vars
        nodes = unique([getnode(var) for var in vars])
        all(node->node in values(getnodesandedges(graph)),nodes)? nothing: error("the linkconstraint: $con contains variables that don't belong to the graph: $graph")
    end
    #Now add the constraints
    for con in cons_refs
        _addlinkconstraint!(graph,con)
    end
end

#Functions specifically for associating models with nodes and edges in a plasmo graph

import JuMP:AbstractModel,AbstractConstraint,Variable,ConstraintRef
import MathProgBase

is_nodevar(nodeoredge::NodeOrEdge,var::Variable) = getmodel(nodeoredge) == var.m #checks whether a variable belongs to a node or edge

#Component Models (A node or edge can have a single model)
function setmodel!(nodeoredge::NodeOrEdge,m::AbstractModel)
    #update link constraints after setting a model
    #_updatelinks(m,nodeoredge)

    !(_assignedtonode(m) && getmodel(nodeoredge) == m) || error("the model is already asigned to another node or edge")
    #@assert !_assignedtonode(m)  #make sure the model isn't already assigned to a different node

    #If it already had a model, delete all the link constraints corresponding to that model
    if hasmodel(nodeoredge)
        for (graph,constraints) in getlinkconstraints(nodeoredge)
            local_link_cons = constraints
            graph_links = getlinkconstraints(graph)
            filter!(c -> !(c in local_link_cons), graph_links)  #filter out local link constraints
            nodeoredge.link_data = NodeLinkData()   #reset the local node or edge link data
        end
    end
    nodeoredge.model = m
    m.ext[:node] = nodeoredge
    #set variable names
    # for i = 1:MathProgBase.numvar(m)
    #     _setvarname(nodeoredge,Variable(m,i))
    # end
end
getnode(m::AbstractModel) = m.ext[:node]
getnode(var::Variable) = var.m.ext[:node]

# TODO  Think of a good way to update links when swapping out models.  Might need to store variable names in NodeLinkData
# function _updatelinks(m,::AbstractModel,nodeoredge::NodeOrEdge)
#     link_cons = getlinkconstraints(nodeoredge)
#     #find variables
# end


_assignedtonode(m::AbstractModel) = haskey(m.ext,:node) #check whether a model is assigned to a node
#_setvarname(nodeoredge::NodeOrEdge,v::Variable) = JuMP.setname(v,string(nodeoredge.label)*"["*getname(v)*"]") #set a variable name when its model gets assigned to a node or edge

#TODO
#set a model with the same variable names and dimensions as the old model on the node.
#This will not break link constraints
function resetmodel!(nodeoredge::NodeOrEdge,m::AbstractModel)
    #reassign the model
    nodeoredge.model = m

    #switch out variables in any connected linkconstraints
    #throw warnings if link constraints break


end

const setmodel = setmodel!
const resetmodel = resetmodel!

#TODO
#removemodel!(nodeoredge::NodeOrEdge) = nodeoredge.attributes[:model] = nothing  #need to update link constraints
# getmodel(nodeoredge::NodeOrEdge) = nodeoredge.attributes[:model]
# hasmodel(nodeoredge::NodeOrEdge) = haskey(nodeoredge.attributes,:model)
getmodel(nodeoredge::NodeOrEdge) = nodeoredge.model
hasmodel(nodeoredge::NodeOrEdge) = nodeoredge.model != nothing? true: false


#getindex(nodeoredge::NodeOrEdge,s::Symbol) = getmodel(nodeoredge)[s]  #get a node or edge variable  THIS GOT MOVED TO JuMP INTERFACE

#Might make more sense to store all link constraints in one place, and use functions to get the right ones
# getlinkconstraints(nodeoredge::NodeOrEdge) = nodeoredge.attributes[:LinkData].linkconstraintmap
# getlinkconstraints(graph::PlasmoGraph,nodeoredge::NodeOrEdge) = nodeoredge.attributes[:LinkData].linkconstraintmap[graph]
# getlinkconstraints(graph::PlasmoGraph) = graph.attributes[:LinkData].linkconstraints
getlinkconstraints(nodeoredge::NodeOrEdge) = nodeoredge.link_data.linkconstraintmap
getlinkconstraints(graph::PlasmoGraph,nodeoredge::NodeOrEdge) = nodeoredge.link_data.linkconstraintmap[graph]
getlinkconstraints(graph::PlasmoGraph) = graph.link_data.linkconstraints


"""
    Get every link constraint in the graph, including subgraphs
"""
function get_all_linkconstraints(graph::PlasmoGraph)
    links = []
    for subgraph in getsubgraphlist(graph)
        append!(links,getlinkconstraints(subgraph))
    end
    append!(links,getlinkconstraints(graph))
    return links
end

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
    push!(graph.link_data.linkconstraints,con)   #add the link constraint to the graph
    for nodeoredge in nodes
        haskey(nodeoredge.link_data.linkconstraintmap,graph)? nothing : nodeoredge.link_data.linkconstraintmap[graph] = Vector{AbstractConstraint}()
        push!(nodeoredge.link_data.linkconstraintmap[graph],con)
    end
end

function _addlinkconstraint!{T}(graph::PlasmoGraph,cons_refs::Array{AbstractConstraint,T})
    array_type = typeof(cons_refs)  #get the array type
    array_type.parameters.length > 1? cons_refs = vec(cons_refs): nothing   #flatten out the constraints into a single vector
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

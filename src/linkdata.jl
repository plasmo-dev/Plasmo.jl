import JuMP:AbstractConstraint,Variable,ConstraintRef

#Link constraint references for nodes and edges (this is useful for inspecting how a particular node is connected to the rest of the graph)
type NodeLinkData
    linkconstraintmap::Dict{AbstractPlasmoGraph,Vector{Union{AbstractConstraint,ConstraintRef}}}  #keep track of constraints linking nodes (or edges) to their neighbors
    #linkvariables::Vector{Variable}
end
NodeLinkData() = NodeLinkData(Dict{AbstractPlasmoGraph,Vector{ConstraintRef}}())

#Tracks all of the link constraints in a graph (but not subgraphs)
type GraphLinkData
     linkconstraints::Vector{AbstractConstraint}  #link constraints between nodes (and edges)
end
GraphLinkData() = GraphLinkData(Vector{AbstractConstraint}())

#typealias LinkData Union{NodeLinkData,GraphLinkData}
const LinkData = Union{NodeLinkData,GraphLinkData}

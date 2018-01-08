import JuMP:AbstractConstraint,Variable,ConstraintRef


#Find a way to grab constraint references.  The JuMP code is pretty complicated to figure out.

#Link constraint references for nodes and edges (this is useful for inspecting how a particular node is connected to the rest of the graph)
mutable struct LinkData
    linkconstraintmap::Dict{AbstractPlasmoGraph,Vector{Union{AbstractConstraint,ConstraintRef}}}  #keep track of constraints linking nodes to their neighbors
    #linkvariables::Vector{Variable}
end
NodeLinkData() = NodeLinkData(Dict{AbstractPlasmoGraph,Vector{ConstraintRef}}())

#Tracks all of the link constraints in a graph (but not subgraphs)
mutable struct GraphLinkData
     linkconstraints::Vector{AbstractConstraint}  #link constraints between nodes
end
GraphLinkData() = GraphLinkData(Vector{AbstractConstraint}())

#typealias LinkData Union{NodeLinkData,GraphLinkData}
#const LinkData = Union{NodeLinkData,GraphLinkData}   #seems like a bad idea


#TODO Write my own Link Constraint type

##############################################################################
# Edges
##############################################################################
struct LinkingEdge <: AbstractLinkingEdge
    baseedge::BasePlasmoEdge
    linkconrefs::Vector{ConstraintRef}
end
#Edge constructors
LinkingEdge() = LinkingEdge(BasePlasmoEdge(),JuMP.ConstraintRef[])
create_edge(graph::ModelGraph) = LinkingEdge()

#Add hyperedge to graph using linkconstraint reference
function add_edge!(graph::AbstractModelGraph,ref::JuMP.ConstraintRef)
    con = LinkConstraint(ref)   #Get the Linkconstraint object so we can inspect the nodes on it
    vars = con.terms.vars
    nodes = unique([getnode(var) for var in vars])  #each var belongs to a node

    edge = add_edge!(graph,nodes...)  #constraint edge connected to more than 2 nodes
    push!(edge.linkconrefs,ref)

    for node in nodes
        if !haskey(node.linkconrefs,graph)
            node.linkconrefs[graph] = [ref]
        else
            push!(node.linkconrefs[graph],ref)
        end
    end
    return edge
end

# TODO  Think of a good way to update links when swapping out models.  Might need to store variable names in NodeLinkData
# function _updatelinks(m,::AbstractModel,nodeoredge::NodeOrEdge)
#     link_cons = getlinkconstraints(nodeoredge)
#     #find variables
# end

struct LinkConstraint{F <: JuMP.AbstractJuMPScalar,S <: MOI.AbstractScalarSet} <: AbstractLinkConstraint
    func::F
    set::S
end
LinkConstraint(con::JuMP.ScalarConstraint) = LinkConstraint(con.func,con.set)

##############################################################################
# LinkEdges
# LinkEdges describe connections between model nodes
##############################################################################
mutable struct LinkEdge <: AbstractLinkEdge
    nodes::OrderedSet{ModelNode}
    #nodes::Set{ModelNode}

    dual_values::Dict{LinkConstraint,Float64}

    #Link references
    linkrefs::Vector{AbstractLinkConstraintRef}

    #Link constraints
    linkconstraints::OrderedDict{Int64,LinkConstraint}                     #Link constraint.  Defined over variables in ModelNodes.
    linkeqconstraints::OrderedDict{Int64,LinkConstraint}
    linkineqconstraints::OrderedDict{Int64,LinkConstraint}
    linkconstraint_names::Dict{Int64,String}
end

struct LinkConstraintRef <: AbstractLinkConstraintRef
    idx::Int                        # index in `model.linkconstraints`
    linkedge::LinkEdge
end
LinkConstraint(ref::LinkConstraintRef) = JuMP.owner_model(ref).linkconstraints[ref.idx]
getnodes(con::LinkConstraint) = [getnode(var) for var in keys(con.func.terms)]  #TODO: Check uniqueness.  It should be unique now that JuMP uses an OrderedDict to store terms.
getnodes(cref::LinkConstraintRef) = getnodes(cref.linkedge)
getnumnodes(con::LinkConstraint) = length(getnodes(con))
JuMP.constraint_object(linkref::LinkConstraintRef) = linkref.linkedge.linkconstraints[linkref.idx]

LinkEdge() = LinkEdge(OrderedSet{ModelNode}(),
                Dict{LinkConstraint,Float64}(),
                Vector{LinkConstraintRef}(),
                OrderedDict{Int, LinkConstraint}(),
                OrderedDict{Int, LinkConstraint}(),
                OrderedDict{Int, LinkConstraint}(),
                OrderedDict{Int64,String}())
LinkEdge(nodes::Vector{ModelNode}) = LinkEdge(OrderedSet(nodes),
                                        Dict{LinkConstraint,Float64}(),
                                        Vector{LinkConstraintRef}(),
                                        OrderedDict{Int, LinkConstraint}(),
                                        OrderedDict{Int, LinkConstraint}(),
                                        OrderedDict{Int, LinkConstraint}(),
                                        OrderedDict{Int64,String}())

num_linkconstraints(edge::LinkEdge) = length(edge.linkconstraints)
getlinkconstraints(edge::LinkEdge) = values(edge.linkconstraints)



function string(edge::LinkEdge)
    "Link edge w/ $(length(edge.linkconstraints)) Constraint(s)"
end
print(io::IO,edge::LinkEdge) = print(io, string(edge))
show(io::IO,edge::LinkEdge) = print(io,edge)

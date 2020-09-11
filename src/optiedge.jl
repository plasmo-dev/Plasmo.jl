"""
    LinkConstraint{F <: JuMP.AbstractJuMPScalar,S <: MOI.AbstractScalarSet} <: AbstractLinkConstraint

Type inherits JuMP.AbstractConstraint.  Contains a func and set used to describe coupling between optinodes.

    LinkConstraint(con::JuMP.ScalarConstraint)

Creates a linking constraint from a JuMP.ScalarConstraint.

    LinkConstraint(ref::LinkConstraintRef)

Retrieves a linking constraint from a LinkConstraintRef.
"""
mutable struct LinkConstraint{F <: JuMP.AbstractJuMPScalar,S <: MOI.AbstractScalarSet} <: AbstractLinkConstraint
    func::F
    set::S
    attached_node::Union{Nothing,OptiNode}
end
LinkConstraint(con::JuMP.ScalarConstraint) = LinkConstraint(con.func,con.set,nothing)

function set_attached_node(con::LinkConstraint,node::OptiNode)
    @assert node in getnodes(con)
    con.attached_node = node
end
##############################################################################
# OptiEdges
# OptiEdges describe connections between model nodes
##############################################################################
"""
    OptiEdge

The `OptiEdge` type.  Typically created from [`@linkconstraint`](@ref).  Contains the set of its supporting optionodes, as well as
references to its underlying linking constraints.
"""
mutable struct OptiEdge <: AbstractOptiEdge
    nodes::OrderedSet{OptiNode}
    #nodes::Set{OptiNode}

    dual_values::Dict{LinkConstraint,Float64}

    #Link references
    linkrefs::Vector{AbstractLinkConstraintRef}

    #Link constraints
    linkconstraints::OrderedDict{Int64,LinkConstraint}                     #Link constraint.  Defined over variables in OptiNodes.
    linkeqconstraints::OrderedDict{Int64,LinkConstraint}
    linkineqconstraints::OrderedDict{Int64,LinkConstraint}
    linkconstraint_names::Dict{Int64,String}
end

struct LinkConstraintRef <: AbstractLinkConstraintRef
    idx::Int                        # index in `model.linkconstraints`
    optiedge::OptiEdge
end
LinkConstraint(ref::LinkConstraintRef) = JuMP.owner_model(ref).linkconstraints[ref.idx]
getnodes(con::LinkConstraint) = [getnode(var) for var in keys(con.func.terms)]  #TODO: Check uniqueness.  It should be unique now that JuMP uses an OrderedDict to store terms.
getnodes(cref::LinkConstraintRef) = getnodes(cref.optiedge)
getnumnodes(con::LinkConstraint) = length(getnodes(con))
JuMP.constraint_object(linkref::LinkConstraintRef) = linkref.optiedge.linkconstraints[linkref.idx]

OptiEdge() = OptiEdge(OrderedSet{OptiNode}(),
                Dict{LinkConstraint,Float64}(),
                Vector{LinkConstraintRef}(),
                OrderedDict{Int, LinkConstraint}(),
                OrderedDict{Int, LinkConstraint}(),
                OrderedDict{Int, LinkConstraint}(),
                OrderedDict{Int64,String}())
OptiEdge(nodes::Vector{OptiNode}) = OptiEdge(OrderedSet(nodes),
                                        Dict{LinkConstraint,Float64}(),
                                        Vector{LinkConstraintRef}(),
                                        OrderedDict{Int, LinkConstraint}(),
                                        OrderedDict{Int, LinkConstraint}(),
                                        OrderedDict{Int, LinkConstraint}(),
                                        OrderedDict{Int64,String}())

num_linkconstraints(edge::OptiEdge) = length(edge.linkconstraints)
getlinkconstraints(edge::OptiEdge) = values(edge.linkconstraints)


function string(edge::OptiEdge)
    "OptiEdge w/ $(length(edge.linkconstraints)) Constraint(s)"
end
print(io::IO,edge::OptiEdge) = print(io, string(edge))
show(io::IO,edge::OptiEdge) = print(io,edge)

function string(con::LinkConstraint)
    "LinkConstraint: $(con.func),$(con.set)"
end
print(io::IO,con::LinkConstraint) = print(io, string(con))
show(io::IO,con::LinkConstraint) = print(io,con)

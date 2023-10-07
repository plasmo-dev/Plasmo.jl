##############################################################################
# LinkConstraint
##############################################################################
"""
    LinkConstraint{F <: JuMP.AbstractJuMPScalar,S <: MOI.AbstractScalarSet} <: AbstractLinkConstraint

Type inherits JuMP.AbstractConstraint.  Contains a func and set used to describe coupling between optinodes.

    LinkConstraint(con::JuMP.ScalarConstraint)

Creates a linking constraint from a JuMP.ScalarConstraint.

    LinkConstraint(ref::LinkConstraintRef)

Retrieves a linking constraint from a LinkConstraintRef.
"""
mutable struct LinkConstraint{F<:JuMP.AbstractJuMPScalar,S<:MOI.AbstractScalarSet} <:
               AbstractLinkConstraint
    func::F
    set::S
    attached_node::Union{Nothing,OptiNode}
end
LinkConstraint(con::JuMP.ScalarConstraint) = LinkConstraint(con.func, con.set, nothing)

"""
    set_attached_node(con::LinkConstraint,node::OptiNode).

Set the linkconstraint `con` to optinode `node`. Mostly useful for algorithms that need an "owning" node on a linkconstraint
"""
function set_attached_node(con::LinkConstraint, node::OptiNode)
    @assert node in optinodes(con)
    return con.attached_node = node
end

"""
    attached_node(con::LinkConstraint)

Retrieve the attached node on linkconstraint `con`
"""
attached_node(con::LinkConstraint) = con.attached_node

##############################################################################
# OptiEdges
##############################################################################
"""
    OptiEdge

The `OptiEdge` type.  Typically created from [`@linkconstraint`](@ref).  Contains the set of its supporting optionodes, as well as
references to its underlying linking constraints.
"""
mutable struct OptiEdge <: AbstractOptiEdge
    nodes::OrderedSet{OptiNode}
    #Link constraint references
    linkrefs::Vector{AbstractLinkConstraintRef}
    #Link constraints
    linkconstraints::OrderedDict{Int64,LinkConstraint}
    linkconstraint_names::OrderedDict{Int64,String}
    backend::EdgeBackend
    #TODO Capture nonlinear linking constraints
    #nlp_data::Union{Nothing,JuMP._NLPData}
end

"""
    LinkConstraintRef

A constraint reference to a linkconstraint. Stores linkconstraint id and the optiedge it belong to.
"""
struct LinkConstraintRef <: AbstractLinkConstraintRef
    idx::Int # index in optiedge
    optiedge::OptiEdge
end
LinkConstraint(ref::LinkConstraintRef) = JuMP.owner_model(ref).linkconstraints[ref.idx]

function OptiEdge()
    return OptiEdge(
        OrderedSet{OptiNode}(),
        Vector{LinkConstraintRef}(),
        OrderedDict{Int,LinkConstraint}(),
        OrderedDict{Int64,String}(),
        EdgeBackend(),
    )
end

function OptiEdge(nodes::Vector{OptiNode})
    optiedge = OptiEdge()
    optiedge.nodes = OrderedSet(nodes)
    return optiedge
end

JuMP.owner_model(cref::LinkConstraintRef) = cref.optiedge
JuMP.jump_function(constraint::LinkConstraint) = constraint.func
JuMP.moi_set(constraint::LinkConstraint) = constraint.set
JuMP.shape(::LinkConstraint) = JuMP.ScalarShape()
function JuMP.constraint_object(cref::LinkConstraintRef, F::Type, S::Type)
    con = cref.optiedge.linkconstraints[cref.idx]
    con.func::F
    con.set::S
    return con
end
function JuMP.set_name(cref::LinkConstraintRef, s::String)
    return JuMP.owner_model(cref).linkconstraint_names[cref.idx] = s
end
JuMP.name(con::LinkConstraintRef) = JuMP.owner_model(con).linkconstraint_names[con.idx]
getname(cref::LinkConstraintRef) = JuMP.name(cref)

function MOI.delete!(cref::LinkConstraintRef)
    delete!(cref.optiedge.linkconstraints, cref.idx)
    return delete!(cref.optiedge.linkconstraint_names, cref.idx)
end
MOI.is_valid(cref::LinkConstraintRef) = haskey(cref.optiedge.linkconstraints, cref.idx)

optinodes(edge::OptiEdge) = edge.nodes
optinodes(con::JuMP.ScalarConstraint) = [optinode(var) for var in keys(con.func.terms)]
optinodes(con::LinkConstraint) = [optinode(var) for var in keys(con.func.terms)]
optinodes(cref::LinkConstraintRef) = optinodes(cref.optiedge.linkconstraints[cref.idx])
num_nodes(con::LinkConstraint) = length(optinodes(con))
function JuMP.constraint_object(linkref::LinkConstraintRef)
    return linkref.optiedge.linkconstraints[linkref.idx]
end

function JuMP.dual(linkref::LinkConstraintRef)
    optiedge = JuMP.owner_model(linkref)
    # this grabs the last solution
    return MOI.get(optiedge.backend, MOI.ConstraintDual(), linkref)
end

num_linkconstraints(edge::OptiEdge) = length(edge.linkconstraints)
linkconstraints(edge::OptiEdge) = values(edge.linkconstraints)
@deprecate getlinkconstraints linkconstraints

function Base.string(edge::OptiEdge)
    return "OptiEdge w/ $(length(edge.linkconstraints)) Constraint(s)"
end
Base.print(io::IO, edge::OptiEdge) = print(io, string(edge))
Base.show(io::IO, edge::OptiEdge) = print(io, edge)

function Base.string(con::AbstractLinkConstraint)
    return "LinkConstraint: $(con.func), $(con.set)"
end
Base.print(io::IO, con::AbstractLinkConstraint) = print(io, string(con))
Base.show(io::IO, con::AbstractLinkConstraint) = print(io, con)

function JuMP.constraint_string(mode::Any, ref::LinkConstraintRef)
    con = JuMP.constraint_object(ref)
    return "$(getname(ref)): $(con.func) $(JuMP.in_set_string(mode,con.set))"
end

function Base.show(io::IO, ref::LinkConstraintRef)
    return print(io, JuMP.constraint_string(MIME("text/plain"), ref))
end
function Base.show(io::IO, ::MIME"text/latex", ref::LinkConstraintRef)
    return print(io, JuMP.constraint_string(MIME("text/latex"), ref))
end

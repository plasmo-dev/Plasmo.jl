
#A constraint between JuMP Models
#Should link constraints be strictly equality?
mutable struct LinkConstraint <: JuMP.AbstractConstraint
    terms::JuMP.AffExpr
    lb::Number
    ub::Number
end
LinkConstraint(con::JuMP.LinearConstraint) = LinkConstraint(con.terms,con.lb,con.ub)

#Get the Link constraint from a reference
LinkConstraint(ref::ConstraintRef) = ref.m.linkdata.linkconstraints[ref.idx]

function getnodes(con::LinkConstraint)
    vars = con.terms.vars
    nodes = unique([getnode(var) for var in vars])
    return nodes
end

#Could just look up the index
function getnumnodes(con::LinkConstraint)
    nodes = getnodes(con)
    return length(nodes)
end


mutable struct LinkData
    linkconstraints::Vector{LinkConstraint}          #all links
    simple_links::Vector{Int}  #references to the 2 node link constraints
    hyper_links::Vector{Int}   #references to linkconstraints with 3 or more nodes
    #hyperconstraints::Vector{LinkConstraint}        #links between 3 or more variables
end
LinkData() = LinkData(Vector{LinkConstraint}(),Vector{Int}(),Vector{Int}())

#A link model is a simple struct that stores link data.
mutable struct LinkModel <: JuMP.AbstractModel   #subtyping here so I can get ConstraintRef
    linkdata::LinkData  #LinkModel's store indices for each link constraint added
    objval::Number
    objective::JuMP.AffExpr  #Possibly a function of multiple model variables
end
LinkModel() = LinkModel(LinkData(),0,JuMP.AffExpr())

getlinkdata(model::LinkModel) = model.linkdata

getsimplelinkconstraints(model::LinkModel) = getlinkdata(model).linkconstraints[getlinkdata(model)[simple_links]]
gethyperlinkconstraints(model::LinkModel) = getlinkdata(model).linkconstraints[getlinkdata(model)[hyper_links]]


is_linkconstr(con::LinkConstraint) = getnumnodes(con) == 2? true : false
is_hyperconstr(con::LinkConstraint) = getnumnodes(con) > 2? true : false

function JuMP.addconstraint(model::LinkModel,constr::JuMP.LinearConstraint)
    #Do some error checking here
    linkdata = getlinkdata(model)
    linkconstr = LinkConstraint(constr)
    push!(linkdata.linkconstraints,linkconstr)
    ref = ConstraintRef{LinkModel,LinkConstraint}(model, length(linkdata.linkconstraints))

    if is_linkconstr(linkconstr )
        push!(linkdata.simple_links,length(linkdata.linkconstraints))
    elseif is_hyperconstr(linkconstr )
        push!(linkdata.hyper_links,length(linkdata.linkconstraints))
    else
        error("constraint doesn't make sense")
    end

    return ref
end


#
#
# const CCAffExpr = JuMP.GenericAffExpr{AffExpr,IndepNormal}
# CCAffExpr() = CCAffExpr(IndepNormal[],AffExpr[],AffExpr())
# #addlinkconstraint!(graph::ModelGraph,con::ConstraintRef)
# type CCData
#     # pure chance constraints
#     chanceconstr
#     # robust chance constraints
#     #robustchanceconstr
#     # two-sided chance constraints
#     twosidechanceconstr
#     numRVs::Int # number of independent normal r.v.'s
#     RVmeans
#     RVvars
#     RVnames
# end
#
# type ChanceConstr <: JuMP.AbstractConstraint
#     ccexpr::CCAffExpr
#     sense::Symbol # :(<=) or :(>=), right-hand side assumed to be zero
#     with_probability::Float64 # with this probability *or greater*
#     uncertainty_budget_mean::Int # for now, with Bertsimas-Sim uncertainty
#     uncertainty_budget_variance::Int # for now, with Bertsimas-Sim uncertainty
# end
#
# ChanceConstr(ccexpr::CCAffExpr,sense::Symbol) = ChanceConstr(ccexpr, sense, NaN, 0, 0)
#
# function JuMP.addconstraint(m::Model, constr::ChanceConstr; with_probability::Float64=NaN, uncertainty_budget_mean::Int=0, uncertainty_budget_variance::Int=0)
#     if !(0 < with_probability < 1)
#         error("Must specify with_probability between 0 and 1")
#     end
#     if with_probability < 0.5
#         error("with_proability < 0.5 is not supported")
#     end
#     constr.with_probability = with_probability
#     constr.uncertainty_budget_mean = uncertainty_budget_mean
#     constr.uncertainty_budget_variance = uncertainty_budget_variance
#
#     ccdata = getCCData(m)  #
#     push!(ccdata.chanceconstr, constr)
#     return ConstraintRef{JuMP.Model,ChanceConstr}(m, length(ccdata.chanceconstr))
#
# end

# #Link constraint references for nodes and edges (this is useful for inspecting how a particular node is connected to the rest of the graph)

# mutable struct LinkData
#     linkconstraintmap::Dict{AbstractPlasmoGraph,Vector{Union{AbstractConstraint,ConstraintRef}}}  #keep track of constraints linking nodes to their neighbors
#     #linkvariables::Vector{Variable}
# end
# NodeLinkData() = NodeLinkData(Dict{AbstractPlasmoGraph,Vector{ConstraintRef}}())
#
# #Tracks all of the link constraints in a graph (but not subgraphs)
# mutable struct GraphLinkData
#      linkconstraints::Vector{AbstractConstraint}  #link constraints between nodes
# end
# GraphLinkData() = GraphLinkData(Vector{AbstractConstraint}())

#typealias LinkData Union{NodeLinkData,GraphLinkData}
#const LinkData = Union{NodeLinkData,GraphLinkData}   #seems like a bad idea

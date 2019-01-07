import ..PlasmoGraphBase:add_node!,add_edge!,create_node,create_edge,getnode,getnodes
import Base:show,print,string,getindex,copy
import JuMP:AbstractModel,setobjective,getobjectivevalue,setsolver,getvalue
import LightGraphs.Graph
import MathProgBase.numvar

##############################################################################
# ModelGraph
##############################################################################
"""
ModelGraph()

The ModelGraph Type.  Represents a graph containing models (nodes) and the linkconstraints (edges) between them.
A ModelGraph wraps a BasePlasmoGraph and can use its methods.  A ModelGraph also wraps a LinkModel object which extends a JuMP AbstractModel to provide model management functions.

"""
mutable struct ModelGraph <: AbstractModelGraph
    basegraph::BasePlasmoGraph                   #Model graph structure.  Put constraint references on edges
    linkmodel::LinkModel                         #Using composition to represent a graph as a "Model".  Someday I will figure out how to do multiple inheritance.
    serial_model::Union{AbstractModel,Nothing}        #The internal serial model for the graph.  Returned if requested by the solve
end

ModelGraph() = ModelGraph(BasePlasmoGraph(HyperGraph),LinkModel(),nothing)
# @deprecate PlasmoGraph ModelGraph
# @deprecate GraphModel ModelGraph

#Write total objective functions for a model graph
_setobjectivevalue(graph::AbstractModelGraph,value::Number) = graph.linkmodel.objval = value

"Set the objective of a ModelGraph"
setobjective(graph::AbstractModelGraph, sense::Symbol, x::JuMP.Variable) = setobjective(graph.linkmodel, sense, convert(AffExpr,x))

"Get the ModelGraph objective value"
JuMP.getobjectivevalue(graph::AbstractModelGraph) = graph.linkmodel.objval

"Get the current created JuMP model for the ModelGraph.  Only created when solving using a JuMP compliant solver."
getinternaljumpmodel(graph::AbstractModelGraph) = graph.serial_model


###
# Solver setters and getters
###
"""
setsolver(model::AbstractModelGraph,solver::AbstractMathProgSolver)

Set the graph solver to use an AbstractMathProg compliant solver
"""
setsolver(model::AbstractModelGraph,solver::AbstractMathProgSolver) = model.linkmodel.solver = solver

"""
setsolver(model::AbstractModelGraph,solver::AbstractPlasmoSolver)

Set the graph solver to use an AbstractMathProg compliant solver
"""
setsolver(model::AbstractModelGraph,solver::AbstractPlasmoSolver) = model.linkmodel.solver = solver

"Get the ModelGraph solver"
getsolver(model::AbstractModelGraph) = model.linkmodel.solver

########################################
# Link Constraints
########################################
#Store link constraint in the given graph.  Store a reference to the linking constraint on the nodes which it links
"Add a single link-constraint to the ModelGraph"
function addlinkconstraint(graph::AbstractModelGraph,con::AbstractConstraint)
    isa(con,JuMP.LinearConstraint) || throw(error("Link constraints must be linear.  If you're trying to add quadtratic or nonlinear links, try creating duplicate variables and linking those"))
    ref = JuMP.addconstraint(graph.linkmodel,con)
    link_edge = add_edge!(graph,ref)  #adds edge and a contraint reference to all objects involved in the constraint
    return link_edge
end

#NOTE Figure out a good way to use containers here instead of making arrays
"Add a vector of link-constraints to the ModelGraph"
function addlinkconstraint(graph::AbstractModelGraph,linkcons::Array{AbstractConstraint,T}) where T
    #NOTE I don't know why I wrote these two lines anymore
    #array_type = typeof(linkcons)   #get the array type
    #array_type.parameters.length > 1 ? linkcons = vec(linkcons) : nothing   #flatten out the constraints into a single vector
    linkcons = vec(linkcons)

    #Check all of the constraints before I add one to the graph
    for con in linkcons
        vars = con.terms.vars
        nodes = unique([getnode(var) for var in vars])
        all(node->node in getnodes(graph),nodes) ? nothing : error("the linkconstraint: $con contains variables that don't belong to the graph: $graph")
    end

    #Now add the constraints
    for con in linkcons
        addlinkconstraint(graph,con)
    end
end

"""
getlinkconstraints(graph::AbstractModelGraph)

Return Array of all LinkConstraints in the ModelGraph graph
"""
getlinkconstraints(model::AbstractModelGraph) = getlinkconstraints(model.linkmodel)

"""
getsimplelinkconstraints(model::AbstractModelGraph)

Retrieve link-constraints that only connect two nodes"
"""
getsimplelinkconstraints(model::AbstractModelGraph) = getsimplelinkconstraints(model.linkmodel)


"""
gethyperlinkconstraints(model::AbstractModelGraph)

Retrieve link-constraints that connect three or more nodes"
"""
gethyperlinkconstraints(model::AbstractModelGraph) = gethyperlinkconstraints(model.linkmodel)

"""
get_all_linkconstraints(graph::AbstractModelGraph)

Get a list containing every link constraint in the graph, including its subgraphs
"""
function get_all_linkconstraints(graph::AbstractModelGraph)
    links = []
    for subgraph in getsubgraphlist(graph)
        append!(links,getlinkconstraints(subgraph))
    end
    append!(links,getlinkconstraints(graph))
    return links
end

#TODO
# function copy(graph::AbstractModelGraph)
#     nodes = getnodes(graph)
#     edges = getedges(graph)
#     copy_graph(graph)
#     Fill in other data
# end


####################################
#Print Functions
####################################
function string(graph::AbstractModelGraph)
    "Model Graph\ngraph_id: "*string(getlabel(graph))*"\nnodes:"*string((length(getnodes(graph))))*"\nsimple links:"*string(length(getsimplelinkconstraints(graph)))*"\nhyper links: "*string(length(gethyperlinkconstraints(graph)))
end
print(io::IO, graph::AbstractModelGraph) = print(io, string(graph))
show(io::IO,graph::AbstractModelGraph) = print(io,graph)

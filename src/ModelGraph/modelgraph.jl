import ..PlasmoGraphBase:add_node!,add_edge!,create_node,create_edge,getnode,getnodes
import Base:show,print,string,getindex,copy
import JuMP:AbstractModel,setobjective,getobjectivevalue,setsolver,getvalue
import LightGraphs.Graph
import MathProgBase.numvar

##############################################################################
# ModelGraph
##############################################################################
#A PlasmoGraph encapsulates a pure graph object wherein nodes and edges are integers and pairs of integers respectively
"The ModelGraph Type.  Represents a system of models and the links between them"
mutable struct ModelGraph <: AbstractModelGraph
    basegraph::BasePlasmoGraph                   #Model graph structure.  Put constraint references on edges
    linkmodel::LinkModel                         #Using composition to represent a graph as a "Model".  Someday I will figure out how to do multiple inheritance.
    serial_model::Nullable{AbstractModel}        #The internal serial model for the graph.  Returned if requested by the solve
end

ModelGraph() = ModelGraph(BasePlasmoGraph(HyperGraph),LinkModel(),Nullable())
@deprecate PlasmoGraph ModelGraph
@deprecate GraphModel ModelGraph
#ModelGraph(lightgraph::LightGraphs.AbstractGraph) = ModelGraph(BasePlasmoGraph(HyperGraph),LinkModel(),Nullable())
#ModelGraph() = ModelGraph(BasePlasmoGraph(Graph),LinkModel(),Nullable())

#Write total objective functions for a model graph
_setobjectivevalue(graph::AbstractModelGraph,value::Number) = graph.linkmodel.objval = value
setobjective(graph::AbstractModelGraph, sense::Symbol, x::JuMP.Variable) = setobjective(graph.linkmodel, sense, convert(AffExpr,x))
getlinkconstraints(model::AbstractModelGraph) = getlinkconstraints(model.linkmodel)
getsimplelinkconstraints(model::AbstractModelGraph) = getsimplelinkconstraints(model.linkmodel)
gethyperlinkconstraints(model::AbstractModelGraph) = gethyperlinkconstraints(model.linkmodel)
JuMP.getobjectivevalue(graph::AbstractModelGraph) = graph.linkmodel.objval
getinternaljumpmodel(graph::AbstractModelGraph) = get(graph.serial_model)

"""
    Get every link constraint in the graph, including subgraphs
"""
function get_all_linkconstraints(graph::AbstractModelGraph)
    links = []
    for subgraph in getsubgraphlist(graph)
        append!(links,getlinkconstraints(subgraph))
    end
    append!(links,getlinkconstraints(graph))
    return links
end
setsolver(model::AbstractModelGraph,solver::AbstractMathProgSolver) = model.linkmodel.solver = solver
setsolver(model::AbstractModelGraph,solver::AbstractPlasmoSolver) = model.linkmodel.solver = solver
getsolver(model::AbstractModelGraph) = model.linkmodel.solver
########################################
# Add the link constraints
########################################
#Store link constraint in the given graph.  Store a reference to the linking constraint on the nodes which it links
function addlinkconstraint(graph::AbstractModelGraph,con::AbstractConstraint)
    isa(con,JuMP.LinearConstraint) || throw(error("Link constraints must be linear.  If you're trying to add quadtratic or nonlinear links, try creating duplicate variables and linking those"))
    ref = JuMP.addconstraint(graph.linkmodel,con)
    link_edge = add_edge!(graph,ref)  #adds edge and a contraint reference to all objects involved in the constraint
    return link_edge
end

#NOTE Figure out a good way to use containers here instead of making arrays
function addlinkconstraint{T}(graph::AbstractModelGraph,linkcons::Array{AbstractConstraint,T})
    array_type = typeof(linkcons)   #get the array type
    array_type.parameters.length > 1? linkcons = vec(linkcons): nothing   #flatten out the constraints into a single vector

    #Check all of the constraints before I add one to the graph
    for con in linkcons
        vars = con.terms.vars
        nodes = unique([getnode(var) for var in vars])
        all(node->node in getnodes(graph),nodes)? nothing: error("the linkconstraint: $con contains variables that don't belong to the graph: $graph")
    end

    #Now add the constraints
    for con in linkcons
        addlinkconstraint(graph,con)
    end
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



# function string(edge::AbstractPlasmoEdge)
#     "edge: "*string(getlabel(edge))*string(" in $(length(getindices(edge))) graph(s) with ids $(collect(values(getindices(edge))))")
# end
# print(io::IO,edge::AbstractPlasmoEdge) = print(io, string(edge))
# show(io::IO,edge::AbstractPlasmoEdge) = print(io,edge)

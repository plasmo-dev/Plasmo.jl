import LightGraphs:AbstractGraph,Graph,DiGraph,add_vertex!,add_edge!,nv,ne,vertices,edges,in_neighbors,out_neighbors,in_edges,out_edges,src,dst,degree
import Base:show,print,string,getindex,copy
import LightGraphs
import JuMP:AbstractModel,Model,UnsetSolver,setsolver,getobjectivevalue,setobjective,AffExpr,Variable
import MathProgBase.SolverInterface:AbstractMathProgSolver

##############################################################################
# Graphs
##############################################################################
#A PlasmoGraph encapsulates a pure graph object wherein nodes and edges are integers and pairs of integers respectively
"The PlasmoGraph Type.  Contains a reference to a LightGraphs.Graph "
type PlasmoGraph <: AbstractPlasmoGraph
    graph::AbstractGraph                        #The underlying lightgraph
    label::Symbol
    index::Integer                              #The index of this graph within a higher level graph (i.e. its index in another graph's subgraphlist) 0 means it isn't a subgraph
    subgraphlist::Vector{AbstractPlasmoGraph}   #How plasmo manages structure
    attributes::Dict{Any,Any}                   #e.g. LinkData; might make primary attributes (like models) into actual fields
    nodes::Dict{Int,AbstractNode}               #Includes nodes in the subgraphs as well
    edges::Dict{LightGraphs.Edge,AbstractEdge}  #Includes edges in the subgraphs as well
    link_data::GraphLinkData
    #nodemap::Dict{Symbol,AbstractNode}         #I'm thinking about also including node and edge maps to reference nodes and edges by a symbol
    #edgemap::Dict{Symbol,AbstractNode}
    internal_serial_model                       #The internal serial model for the graph.  Created by aggregating node models and link constraints in the graph
    solver::AbstractMathProgSolver              #for solve(graph)
    objVal::Number
    objective
end

"""
PlasmoGraph()

Creates an empty PlasmoGraph
"""
PlasmoGraph() = PlasmoGraph(DiGraph(),gensym(),0,AbstractGraph[],Dict(),Dict{Int,AbstractNode}(),Dict{LightGraphs.Edge,AbstractEdge}(),GraphLinkData(),nothing,UnsetSolver(),NaN,nothing)
const GraphModel = PlasmoGraph

"""
PlasmoGraph(::AbstractGraph)

Creates a PlasmoGraph given a LightGraph object
"""
function PlasmoGraph(g::AbstractGraph)  #build a graph from a LightGraph
    pgraph = PlasmoGraph(g,gensym(),0,AbstractGraph[],Dict(),Dict{Int,AbstractNode}(),Dict{LightGraphs.Edge,AbstractEdge}(),GraphLinkData(),nothing,UnsetSolver(),NaN,nothing)
    for vertex in vertices(g)
        pgraph.nodes[vertex] = PlasmoNode(Dict(pgraph => vertex),Symbol("node"*string(vertex)),Dict(),Model(),NodeLinkData())
    end
    for edge in edges(g)
        pgraph.edges[edge] = PlasmoEdge(Dict(pgraph => edge),Symbol("edge"*string(edge)),Dict(),Model(),NodeLinkData())
    end
    return pgraph
end

"""
    getindex(:PlasmoGraph)

    Get the index of a subgraph within EACH of its graphs.  Returns 0 if the graph is not a subgraph.
"""
getindex(graph::PlasmoGraph) = graph.index

setsolver(graph::PlasmoGraph,solver::AbstractMathProgSolver) = graph.solver = solver
_setobjectivevalue(graph::PlasmoGraph,num::Number) = graph.objVal = num
getgraphobjectivevalue(graph::PlasmoGraph) = graph.objVal
getobjectivevalue(graph::PlasmoGraph) = graph.objVal
getinternalgraphmodel(graph::PlasmoGraph) = graph.internal_serial_model

# setobjective(graph::PlasmoGraph, sense::Symbol, x::Variable) = setobjective(graph, sense, convert(AffExpr,x))
# function setobjective(m::Model, sense::Symbol, a::AffExpr)
#     if length(graph.obj.qvars1) != 0
#         # Go through the quadratic path so that we properly clear
#         # current quadratic terms.
#         setobjective(graph, sense, convert(QuadExpr,a))
#     else
#         setobjectivesense(m, sense)
#         m.obj = convert(QuadExpr,a)
#     end
# end

##############################################################################
# Nodes
##############################################################################
#Nodes and edges are integers and pairs.  When adding nodes, it creates the plasmo node data structure and also adds the vertex to the underlying lightgraph
#A Plasmo Node maps to a PlasmoGraph.  It holds an index to its integer in the underlying graph and holds its own attributes.
type PlasmoNode <: AbstractNode
    index::Dict{PlasmoGraph,Int} #map to an index in each graph containing the node
    label::Symbol
    attributes::Dict{Any,Any}  #A model is an attribute
    model::AbstractModel
    link_data::NodeLinkData
end

# Node constructors
PlasmoNode() = PlasmoNode(Dict{PlasmoGraph,Int}(), Symbol("node"),Dict{Any,Any}(),Model(),NodeLinkData())
function PlasmoNode(g::PlasmoGraph)
    add_vertex!(g.graph)
    i = nv(g.graph)
    label = Symbol("node"*string(i))
    node = PlasmoNode(Dict(g => i),label,Dict(),Model(),NodeLinkData())
    g.nodes[i] = node
    return node
end

#Add an existing node to a graph.  It's possible to pass a user specified index.  This is useful for copying graphs
function add_node!(g::AbstractPlasmoGraph,node::AbstractNode;index = nv(g.graph)+1)
    add_vertex!(g.graph)
    #i = nv(g.graph)
    node.index[g] = index #sets a dictionary reference
    g.nodes[index] = node #sets the graph reference to the node
    return node
end
create_node() = PlasmoNode()
add_node!(g::PlasmoGraph) = PlasmoNode(g)
add_vertex!(g::PlasmoGraph) = PlasmoNode(g)
add_vertex!(g::PlasmoGraph,node::PlasmoNode) = add_node!(g,node)


##############################################################################
# Edges
##############################################################################
#A Plasmo Edge maps to a PlasmoGraph.  It holds an index to its edge in the underlying graph and holds its own attributes
type PlasmoEdge <: AbstractEdge
    index::Dict{AbstractPlasmoGraph,LightGraphs.Edge}
    label::Symbol
    attributes::Dict
    model::AbstractModel
    link_data::NodeLinkData
end
#Edge constructors
PlasmoEdge() = PlasmoEdge(Dict{AbstractPlasmoGraph,LightGraphs.Edge}(), Symbol("edge"),Dict{Any,Any}(),Model(),NodeLinkData())
function PlasmoEdge(g::AbstractPlasmoGraph,edge::LightGraphs.Edge)
    add_edge!(g.graph,edge)
    label = Symbol("edge"*string(edge))
    pedge = PlasmoEdge(Dict(g => edge),label,Dict(),Model(),NodeLinkData())
    g.edges[edge] = pedge
    return pedge
end

function add_edge!(g::AbstractPlasmoGraph,pedge::AbstractEdge,src::AbstractNode,dst::AbstractNode)
    edge = LightGraphs.Edge(src.index[g],dst.index[g])
    add_edge!(g.graph,edge)
    label = Symbol("edge"*string(edge))
    pedge.index[g] = edge
    g.edges[edge] = pedge
    return pedge
end
add_edge!(g::AbstractPlasmoGraph,edge::LightGraphs.Edge) = PlasmoEdge(g,edge)
add_edge!(g::AbstractPlasmoGraph,src::Int,dst::Int) = PlasmoEdge(g,LightGraphs.Edge(src,dst))
add_edge!(g::AbstractPlasmoGraph,src::AbstractNode,dst::AbstractNode) = PlasmoEdge(g,LightGraphs.Edge(src.index[g],dst.index[g]))



#Setting and getting Graph Properties
getnodes(g::AbstractPlasmoGraph) = g.nodes  #dictionary
getedges(g::AbstractPlasmoGraph) = g.edges  #dictionary
getsubgraphlist(g::PlasmoGraph) = g.subgraphlist
getnode(g::PlasmoGraph,i::Int) = g.nodes[i]
getedge(g::PlasmoGraph,edge::LightGraphs.Edge) = g.edges[edge]
function getnodesandedges(g::AbstractPlasmoGraph)
    d = Dict{Union{Int,LightGraphs.Edge},NodeOrEdge}()
    merge!(d,getnodes(g))
    merge!(d,getedges(g))
    return d
end
getnodeoredge(g::AbstractPlasmoGraph,i::Union{Int,LightGraphs.Edge}) = isa(i,Int)? getnode(g,i): getedge(g,i)


getnodeindex(g::AbstractPlasmoGraph,node::AbstractNode) = node.index[g]
getedgeindex(g::AbstractPlasmoGraph,edge::AbstractEdge) = edge.index[g]

copy(node::PlasmoNode) = nothing
copy(edge::PlasmoEdge) = nothing

"""
    getindex(::PlasmoGraph,::NodeOrEdge)
    Get the index of a node or edge within a PlasmoGraph
"""
getindex(g::AbstractPlasmoGraph,nodeoredge::NodeOrEdge) = nodeoredge.index[g]
"""
    getindex(::PlasmoGraph,::NodeOrEdge)
    Return a dictionary of a node's or edge's index in each of its graphs.
"""
getindex(nodeoredge::NodeOrEdge) = nodeoredge.index

#Print Functions
string(graph::AbstractPlasmoGraph) = "plasmo graph: "*string(graph.label)*"\n"*string(graph.graph)
print(io::IO, graph::AbstractPlasmoGraph) = print(io, string(graph))
show(io::IO,graph::AbstractPlasmoGraph) = print(io,graph)

string(node::AbstractNode) = "plasmo node: "*string(node.label)*string(node.index)
print(io::IO,node::AbstractNode) = print(io, string(node))
show(io::IO,node::AbstractNode) = print(io,node)

string(edge::AbstractEdge) = "plasmo edge: "*string(edge.label)
print(io::IO,edge::AbstractEdge) = print(io, string(edge))
show(io::IO,edge::AbstractEdge) = print(io,edge)

##############################################################################
# Attributes
##############################################################################
#add or remove attributes from graphs, nodes, and edges
function addattribute!(graph::AbstractPlasmoGraph,attribute::Symbol,value)
    graph.attributes[attribute] = value
end
function addattribute!(item::NodeOrEdge,attribute::Symbol,value)
    item.attributes[attribute] = value
end
function addattribute!(g::AbstractPlasmoGraph,i::Int,attribute::Symbol,value)
    node = g.nodes[i]
    addattribute!(node,attribute,value)
end
function addattribute!(g::AbstractPlasmoGraph,edge::LightGraphs.Edge,attribute::Symbol,value)
    pedge = g.edges[edge]
    addattribute!(pedge,attribute,value)
end
getattribute(item::NodeOrEdge,attribute::Symbol) = item.attributes[attribute]
hasattribute(item::NodeOrEdge,attribute::Symbol) = haskey(item.attributes,attribute)

rmattribute!(item::NodeOrEdge,attribute::Symbol) = delete!(item.attributes,attribute)
rmattribute!(graph::AbstractPlasmoGraph,attribute::Symbol) = delete!(graph.attributes,attribute)

##############################################################################
# Subgraphs
##############################################################################
#Managing subgraphs
#Add nodes, but don't add edges.  neighbors, degree, etc... are graph specific
function add_subgraph!(graph::PlasmoGraph,subgraph::PlasmoGraph)
    push!(graph.subgraphlist,subgraph)
    subgraph.index = length(graph.subgraphlist)
    for (index,node) in getnodes(subgraph)
        add_node!(graph,node)
    end
    return graph
end

getsubgraph(graph::PlasmoGraph,index::Int) = graph.subgraphlist[index]

#copy the subgraph structure from one graph to another
function _copy_subgraphs!(graph1::AbstractPlasmoGraph,graph2::AbstractPlasmoGraph)
    for i = 1:length(graph1.subgraphlist)
        subgraph = PlasmoGraph()
        add_subgraph!(graph2,subgraph)
    end
end

#Add the edges too
function add_induced_subgraph!()
end

#get all nodes and edges in a single graph
function getcompletegraph(graph::PlasmoGraph)
end
##############################################################################
# Topology
##############################################################################
#Topology functions (LightGraphs extensions)
src(pgraph::AbstractPlasmoGraph,edge::AbstractEdge) = getnode(pgraph,LightGraphs.src(edge.index[pgraph]))  #source node of a Plasmo Edge
dst(pgraph::AbstractPlasmoGraph,edge::AbstractEdge) = getnode(pgraph,LightGraphs.dst(edge.index[pgraph]))  #destination node of a Plasmo Edge
src(pgraph::AbstractPlasmoGraph,edge::LightGraphs.Edge) = getnode(pgraph,LightGraphs.src(edge))  #source node of a Plasmo Edge
dst(pgraph::AbstractPlasmoGraph,edge::LightGraphs.Edge) = getnode(pgraph,LightGraphs.dst(edge))  #destination node of a Plasmo Edge

in_edges(pgraph::AbstractPlasmoGraph,node::AbstractNode) = [pgraph.edges[LightGraphs.Edge(in_node,getindex(pgraph,node))] for in_node in LightGraphs.in_neighbors(pgraph.graph,getindex(pgraph,node))]
out_edges(pgraph::AbstractPlasmoGraph,node::AbstractNode) = [pgraph.edges[LightGraphs.Edge(getindex(pgraph,node),out_node)] for out_node in LightGraphs.out_neighbors(pgraph.graph,getindex(pgraph,node))]

in_neighbors(pgraph::AbstractPlasmoGraph,node::AbstractNode) = [pgraph.nodes[node] for node in LightGraphs.in_neighbors(pgraph.graph,getindex(pgraph,node))]
out_neighbors(pgraph::AbstractPlasmoGraph,node::AbstractNode) = [pgraph.nodes[node] for node in LightGraphs.out_neighbors(pgraph.graph,getindex(pgraph,node))]
neighbors(pgraph::AbstractPlasmoGraph,node::AbstractNode) = [pgraph.nodes[node] for node in LightGraphs.all_neighbors(pgraph.graph,getindex(pgraph,node))]


getsupportingedges(pgraph::AbstractPlasmoGraph,node::AbstractNode) = [in_edges(pgraph,node);out_edges(pgraph,node)]

getconnectedfrom(pgraph::AbstractPlasmoGraph,edge::AbstractEdge) = src(pgraph,edge)
getconnectedto(pgraph::AbstractPlasmoGraph,edge::AbstractEdge) = dst(pgraph,edge)
getsupportingnodes(pgraph::AbstractPlasmoGraph,edge::AbstractEdge) = tuple(src(pgraph,edge),dst(pgraph,edge))
getsupportingnodes(pgraph::AbstractPlasmoGraph,edge::LightGraphs.Edge) = tuple(src(pgraph,edge),dst(pgraph,edge))

degree(pgraph::AbstractPlasmoGraph,node::AbstractNode) = degree(pgraph.graph,node.index[pgraph])
in_degree(pgraph::AbstractPlasmoGraph,node::AbstractNode) = length(in_neighbors(pgraph,node))
out_degree(pgraph::AbstractPlasmoGraph,node::AbstractNode) = length(out_neighbors(pgraph,node))

is_connected(graph::AbstractPlasmoGraph,n1::AbstractNode,n2::AbstractNode)  = n2 in neighbors(graph,n1)
is_connected(graph::AbstractPlasmoGraph,node::AbstractNode,edge::AbstractEdge)  = edge in getsupportingedges(graph,node)
is_connected(graph::AbstractPlasmoGraph,edge::AbstractEdge,node::AbstractNode)  = edge in getsupportingedges(graph,node)
is_connected(graph::AbstractPlasmoGraph,edge1::AbstractEdge,edge2::AbstractEdge)  = !isempty(intersect(getsupportingnodes(graph,edge1),getsupportingnodes(graph,edge2)))

##########################################
# Other useful functions
##########################################
"""
    contains_node(g::PlasmoGraph,n::NodeOrEdge)
    return whether a PlasmoGraph:g, contains the given node or edge: n
"""
contains_node(graph::AbstractPlasmoGraph,nodeoredge::NodeOrEdge) = nodeoredge in [graph.nodes;graph.edges]
# typealias Node PlasmoNode
# typealias Edge PlasmoEdge
# typealias GraphModel PlasmoGraph

const Node = PlasmoNode
const Edge = PlasmoEdge
const GraphModel = PlasmoGraph

#add_node and add_edge and add_subgraph without the !
const add_node = add_node!
const add_edge = add_edge!
const add_subgraph = add_subgraph!


#TODO
#add_neighbor!(graph,node)

#Might need this function?  Depends if we're using normal graphs, or directed graphs
# function sort(g::PlasmoGraph,e::Edge)
#     if isa(g.graph,Graph)
#         return e[1] <= e[2] ? e : reverse(e)
#     elseif isa(g.graph,DiGraph)
#         return e
#     end
# end

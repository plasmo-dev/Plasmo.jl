import LightGraphs:AbstractGraph,AbstractEdge,Graph,DiGraph,add_vertex!,add_edge!,nv,ne,vertices,edges,in_neighbors,out_neighbors,in_edges,out_edges,src,dst,degree
import Base:show,print,string,getindex,copy
import LightGraphs
import JuMP:AbstractModel,Model,UnsetSolver,setsolver,getobjectivevalue,setobjective,AffExpr,Variable
import MathProgBase.SolverInterface:AbstractMathProgSolver

##############################################################################
# PlasmoGraph
##############################################################################
#A PlasmoGraph encapsulates a pure graph object wherein nodes and edges are integers and pairs of integers respectively
"The PlasmoGraph Type.  Contains a reference to a LightGraphs.Graph "
mutable struct PlasmoGraph <: AbstractPlasmoGraph
    graph::AbstractGraph                        #The underlying lightgraph
    label::Symbol
    index::Integer                              #The index of this graph within a higher level graph (i.e. its index in another graph's subgraphlist) 0 means it isn't a subgraph
    subgraphlist::Vector{AbstractPlasmoGraph}   #How plasmo manages structure
    attributes::Dict{Any,Any}                   #e.g. LinkData; might make primary attributes (like models) into actual fields

    nodedict::NodeDict                          #Includes nodes in the subgraphs as well
    edgedict::EdgeDict                          #Includes edges in the subgraphs as well

    link_data::GraphLinkData                    #Link constraint information
    internal_serial_model                      #The internal serial model for the graph.  Created by aggregating node models and link constraints in the graph
    solver::AbstractMathProgSolver              #Set a mathprogbase compliant solver
    objVal::Number                              #Objective value
    objective                                   #Objective object
end

"""
PlasmoGraph()

Creates an empty PlasmoGraph
"""
#NOTE Graph or DiGraph here?
#PlasmoGraph() = PlasmoGraph(DiGraph(),gensym(),0,AbstractGraph[],Dict(),Dict{Int,AbstractNode}(),Dict{LightGraphs.Edge,AbstractEdge}(),GraphLinkData(),nothing,UnsetSolver(),NaN,nothing)
PlasmoGraph() = PlasmoGraph(LightGraphs.Graph(),gensym(),0,AbstractGraph[],Dict(),NodeDict(),EdgeDict(),GraphLinkData(),nothing,UnsetSolver(),NaN,nothing)
#const GraphModel = PlasmoGraph

"""
PlasmoGraph(::AbstractGraph)

Creates a PlasmoGraph given a LightGraph AbstractGraph
"""
#TODO Get this working
function PlasmoGraph(lightgraph::AbstractGraph)  #build a graph from a LightGraph
    plasmograph = PlasmoGraph(lightgraph,gensym(),0,AbstractGraph[],Dict(),NodeDict(),EdgeDict(),GraphLinkData(),nothing,UnsetSolver(),NaN,nothing)
    for vertex in vertices(lightgraph)
        add_node!(plasmograph)
        #pgraph.nodes[vertex] = PlasmoNode(Dict(pgraph => vertex),Symbol("node"*string(vertex)),Dict(),Model(),LinkData())
    end
    for edge in edges(lightgraph) #these are AbstractEdges...
        add_edge!(plasmograph,edge)
        #plasmograph.edges[edge] = PlasmoEdge(Dict(pgraph => edge),Symbol("edge"*string(edge)),Dict(),Model(),LinkData())
        #add_edge!(pgraph)
    end
    return plasmograph
end


"""
    getindex(:PlasmoGraph)

    Get the index of a subgraph within EACH of its graphs.  Returns 0 if the graph is not a subgraph.
"""
getindex(graph::PlasmoGraph) = graph.index


##############################################################################
# Nodes
##############################################################################
#Nodes and edges are integers and pairs.  When adding nodes, it creates the plasmo node data structure and also adds the vertex to the underlying lightgraph
#A Plasmo Node maps to a PlasmoGraph.  It holds an index to its integer in the underlying graph and holds its own attributes.
mutable struct PlasmoNode <: AbstractPlasmoNode
    indices::Dict{AbstractPlasmoGraph,Int} #map to an index in each graph containing the node
    label::Symbol
    attributes::Dict{Any,Any}   #data,etc...
    model::AbstractModel        #might do something else to initialize
    link_data::LinkData
end

#Node constructors
#empty PlasmoNode
PlasmoNode() = PlasmoNode(Dict{PlasmoGraph,Int}(),
                            Symbol("node"),
                            Dict{Any,Any}(),
                            Model(),
                            LinkData())
create_node() = PlasmoNode()

function PlasmoNode(g::PlasmoGraph)
    add_vertex!(g.graph)
    index = nv(g.graph)
    label = Symbol("node"*string(index))
    node = create_node()
    node.indices[g] = index
    add_node!(g.node_dict,node,index)
    return node
end

#Add an existing node to a graph.  It's possible to pass a user specified index.  This is useful for copying graphs
function add_node!(graph::AbstractPlasmoGraph,node::AbstractPlasmoNode;index = nv(g.graph)+1)
    add_vertex!(graph.graph)                #add the light graph vertex
    node.indices[graph] = index
    add_node!(graph.node_dict,node,index)   #add the node at the given index
    return node
end

add_node!(g::PlasmoGraph) = PlasmoNode(g)

##############################################################################
# Edges
##############################################################################
#More or less copied from LightGraphs.jl
struct SimpleEdge <: AbstractEdge
    src::Int
    dst::Int
end
SimpleEdge(t::Tuple) = SimpleEdge(t[1], t[2])
SimpleEdge(p::Pair) = SimpleEdge(p.first, p.second)

#A Plasmo Edge maps to a PlasmoGraph.  It holds an index to its edge in the underlying graph and holds its own attributes
mutable struct PlasmoEdge <: AbstractPlasmoEdge
    indices::Dict{AbstractPlasmoGraph,AbstractEdge}  #index in each graph
    link_data::LinkData
end
#Edge constructors
PlasmoEdge() = PlasmoEdge(Dict{AbstractPlasmoGraph,AbstractEdge}(),LinkData())
create_edge() = PlasmoEdge()

function PlasmoEdge(graph::AbstractPlasmoGraph,edge::AbstractEdge)
    add_edge!(graph.graph,edge)                         #add the edge to the lightgraph
    pedge = PlasmoEdge(Dict(graph => edge),LinkData())  #create empty plasmo edge
    add_edge!(graph.edge_dict,pedge,edge)               #add to the edge dictionary
    return pedge
end

function add_edge!(graph::AbstractPlasmoGraph,pedge::AbstractPlasmoEdge,src::AbstractPlasmoNode,dst::AbstractPlasmoNode)
    edge = SimpleEdge(src.indices[g],dst.indices[g])
    add_edge!(graph.graph,edge)
    pedge.indices[graph] = edge
    add_edge!(graph.edge_dict,pedge,edge)
    return pedge
end
add_edge!(g::AbstractPlasmoGraph,pair::Pair) = PlasmoEdge(g,SimpleEdge(pair))
add_edge!(g::AbstractPlasmoGraph,src::Int,dst::Int) = PlasmoEdge(g,SimpleEdge(src,dst))
add_edge!(g::AbstractPlasmoGraph,src::AbstractPlasmoNode,dst::AbstractPlasmoNode) = PlasmoEdge(g,SimpleEdge(src.index[g],dst.index[g]))


#Setting and getting Graph Properties
getnodes(g::AbstractPlasmoGraph) = nodes(g.nodedict)  #dictionary
getedges(g::AbstractPlasmoGraph) = edges(g.edgedict)  #dictionary
getsubgraphlist(g::PlasmoGraph) = g.subgraphlist
getnode(g::AbstractPlasmoGraph,i::Int) = g.nodedict.id_dict[i]
getedge(g::AbstractPlasmoGraph,edge::AbstractEdge) = g.edgedict.id_dict[edge]
getedge(g::AbstractPlasmoGraph,pair::Pair) = g.edgedict.id_dict[SimpleEdge(pair)]
getedge(g::AbstractPlasmoGraph,tuple::Tuple) = g.edgedict.id_dict[SimpleEdge(tuple[1],tuple[2])]
# function getnodesandedges(g::AbstractPlasmoGraph)
#     d = Dict{Union{Int,LightGraphs.Edge},NodeOrEdge}()
#     merge!(d,getnodes(g))
#     merge!(d,getedges(g))
#     return d
# end
# getnodeoredge(g::AbstractPlasmoGraph,i::Union{Int,LightGraphs.Edge}) = isa(i,Int)? getnode(g,i): getedge(g,i)

"""
    getgraphindices(::NodeOrEdge)
    Return a dictionary of a node's or edge's index in each of its graphs.
"""
getgraphindices(node::AbstractPlasmoNode) = node.indices
getgraphindices(edge::AbstractPlasmoEdge) = edge.indices
getindex(g::AbstractPlasmoGraph,node::AbstractPlasmoNode) = node.indices[g]
getindex(g::AbstractPlasmoGraph,edge::AbstractPlasmoEdge) = edge.indices[g]

# copy(node::PlasmoNode) = nothing
# copy(edge::PlasmoEdge) = nothing

##############################################################################
# Attributes
##############################################################################
#add or remove attributes from graphs, nodes, and edges
function addattribute!(graph::AbstractPlasmoGraph,attribute::Symbol,value)
    graph.attributes[attribute] = value
end
function addattribute!(node::AbstractPlasmoNode,attribute::Symbol,value)
    node.attributes[attribute] = value
end
function addattribute!(g::AbstractPlasmoGraph,i::Int,attribute::Symbol,value)
    node = getnode(g,i)
    addattribute!(node,attribute,value)
end

getattribute(node::AbstractPlasmoNodee,attribute::Symbol) = node.attributes[attribute]
hasattribute(node::AbstractPlasmoNode,attribute::Symbol) = haskey(node.attributes,attribute)

rmattribute!(node::AbstractPlasmoNode,attribute::Symbol) = delete!(node.attributes,attribute)
rmattribute!(graph::AbstractPlasmoGraph,attribute::Symbol) = delete!(graph.attributes,attribute)

##############################################################################
# Subgraphs
##############################################################################
#Managing subgraphs
#Add nodes, but don't add edges.  neighbors, degree, etc... are graph specific
function add_subgraph!(graph::AbstractPlasmoGraph,subgraph::AbstractPlasmoGraph)
    push!(graph.subgraphlist,subgraph)
    subgraph.index = length(graph.subgraphlist)
    for node in getnodes(subgraph)
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
src(pgraph::AbstractPlasmoGraph,pedge::AbstractPlasmoEdge) = getnode(pgraph,LightGraphs.src(pedge.indices[pgraph]))  #source node of a Plasmo Edge
dst(pgraph::AbstractPlasmoGraph,pedge::AbstractPlasmoEdge) = getnode(pgraph,LightGraphs.dst(pedge.indices[pgraph]))  #destination node of a Plasmo Edge
src(pgraph::AbstractPlasmoGraph,edge::AbstractEdge) = getnode(pgraph,LightGraphs.src(edge))  #source node of a Plasmo Edge
dst(pgraph::AbstractPlasmoGraph,edge::AbstractEdge) = getnode(pgraph,LightGraphs.dst(edge))  #destination node of a Plasmo Edge

in_edges(pgraph::AbstractPlasmoGraph,node::AbstractPlasmoNode) = [pgraph.edges[SimpleEdge(in_node,getindex(pgraph,node))] for in_node in LightGraphs.in_neighbors(pgraph.graph,getindex(pgraph,node))]
out_edges(pgraph::AbstractPlasmoGraph,node::AbstractPlasmoNode) = [pgraph.edges[SimpleEdge(getindex(pgraph,node),out_node)] for out_node in LightGraphs.out_neighbors(pgraph.graph,getindex(pgraph,node))]

in_neighbors(pgraph::AbstractPlasmoGraph,node::AbstractPlasmoNode) = [pgraph.nodes[node] for node in LightGraphs.in_neighbors(pgraph.graph,getindex(pgraph,node))]
out_neighbors(pgraph::AbstractPlasmoGraph,node::AbstractPlasmoNode) = [pgraph.nodes[node] for node in LightGraphs.out_neighbors(pgraph.graph,getindex(pgraph,node))]
neighbors(pgraph::AbstractPlasmoGraph,node::AbstractPlasmoNode) = [pgraph.nodes[node] for node in LightGraphs.all_neighbors(pgraph.graph,getindex(pgraph,node))]


getsupportingedges(pgraph::AbstractPlasmoGraph,node::AbstractPlasmoNode) = [in_edges(pgraph,node);out_edges(pgraph,node)]

getconnectedfrom(pgraph::AbstractPlasmoGraph,edge::AbstractPlasmoEdge) = src(pgraph,edge)
getconnectedto(pgraph::AbstractPlasmoGraph,edge::AbstractPlasmoEdge) = dst(pgraph,edge)
getsupportingnodes(pgraph::AbstractPlasmoGraph,edge::AbstractPlasmoEdge) = tuple(src(pgraph,edge),dst(pgraph,edge))
getsupportingnodes(pgraph::AbstractPlasmoGraph,edge::AbstractEdge) = tuple(src(pgraph,edge),dst(pgraph,edge))

degree(pgraph::AbstractPlasmoGraph,node::AbstractPlasmoNode) = degree(pgraph.graph,node.index[pgraph])
in_degree(pgraph::AbstractPlasmoGraph,node::AbstractPlasmoNode) = length(in_neighbors(pgraph,node))
out_degree(pgraph::AbstractPlasmoGraph,node::AbstractPlasmoNode) = length(out_neighbors(pgraph,node))

is_connected(graph::AbstractPlasmoGraph,n1::AbstractPlasmoNode,n2::AbstractPlasmoNode)  = n2 in neighbors(graph,n1)
is_connected(graph::AbstractPlasmoGraph,node::AbstractPlasmoNode,edge::AbstractEdge)  = edge in getsupportingedges(graph,node)
is_connected(graph::AbstractPlasmoGraph,edge::AbstractPlasmoEdge,node::AbstractPlasmoNode)  = edge in getsupportingedges(graph,node)
is_connected(graph::AbstractPlasmoGraph,edge1::AbstractPlasmoEdge,edge2::AbstractPlasmoEdge)  = !isempty(intersect(getsupportingnodes(graph,edge1),getsupportingnodes(graph,edge2)))

##########################################
# Other useful functions
##########################################
"""
    contains_node(g::PlasmoGraph,n::NodeOrEdge)
    return whether a PlasmoGraph:g, contains the given node or edge: n
"""
contains_node(graph::AbstractPlasmoGraph,node::AbstractPlasmoNode) = node in graph.nodedict
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

#Print Functions
string(graph::AbstractPlasmoGraph) = "plasmo graph: "*string(graph.label)*"\n"*string(graph.graph)
print(io::IO, graph::AbstractPlasmoGraph) = print(io, string(graph))
show(io::IO,graph::AbstractPlasmoGraph) = print(io,graph)

string(node::AbstractPlasmoNode) = "plasmo node: "*string(node.label)*string(node.index)
print(io::IO,node::AbstractPlasmoNode) = print(io, string(node))
show(io::IO,node::AbstractPlasmoNode) = print(io,node)

string(edge::AbstractEdge) = "plasmo edge: "*string(edge.label)
print(io::IO,edge::AbstractEdge) = print(io, string(edge))
show(io::IO,edge::AbstractEdge) = print(io,edge)
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

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

    # nodes::Vector{AbstractNode}               #Includes nodes in the subgraphs as well
    # edges::Vector{AbstractEdge}               #Includes edges in the subgraphs as well

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
PlasmoGraph() = PlasmoGraph(Graph(),gensym(),0,AbstractGraph[],Dict(),NodeDict(),EdgeDict(),GraphLinkData(),nothing,UnsetSolver(),NaN,nothing)
#const GraphModel = PlasmoGraph

"""
PlasmoGraph(::AbstractGraph)

Creates a PlasmoGraph given a LightGraph AbstractGraph
"""
#TODO Get this working
function PlasmoGraph(g::AbstractGraph)  #build a graph from a LightGraph
    pgraph = PlasmoGraph(g,gensym(),0,AbstractGraph[],Dict(),NodeDict(),EdgeDict(),GraphLinkData(),nothing,UnsetSolver(),NaN,nothing)
    for vertex in vertices(g)
        add_node!(pgraph)
        #pgraph.nodes[vertex] = PlasmoNode(Dict(pgraph => vertex),Symbol("node"*string(vertex)),Dict(),Model(),LinkData())
    end
    for edge in edges(g) #these are AbstractEdges...
        pgraph.edges[edge] = PlasmoEdge(Dict(pgraph => edge),Symbol("edge"*string(edge)),Dict(),Model(),LinkData())
        #add_edge!(pgraph)
    end
    return pgraph
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
    model::AbstractModel
    link_data::LinkData
end

# Node constructors
PlasmoNode() = PlasmoNode(Dict{PlasmoGraph,Int}(),
                            Symbol("node"),
                            Dict{Any,Any}(),
                            Model(),
                            LinkData())
create_node() = PlasmoNode()    #empty PlasmoNode

function PlasmoNode(g::PlasmoGraph)
    add_vertex!(g.graph)
    index = nv(g.graph)
    label = Symbol("node"*string(index))
    node = create_node()
    #push!(g.node_dict,node)
    g.node_dict[node] = index
    #g.nodes[i] = node
    return node
end

#Add an existing node to a graph.  It's possible to pass a user specified index.  This is useful for copying graphs
function add_node!(g::AbstractPlasmoGraph,node::AbstractPlasmoNode;index = nv(g.graph)+1)
    add_vertex!(g.graph)     #add the light graph vertex
    node.index[g] = index    #sets the node index in the graph
    g.node_dict[node] = index
    #push!(g.node_dict,node)
    #g.nodes[index] = node #sets the graph reference to the node
    return node
end

add_node!(g::PlasmoGraph) = PlasmoNode(g)

##############################################################################
# Edges
##############################################################################
#A Plasmo Edge maps to a PlasmoGraph.  It holds an index to its edge in the underlying graph and holds its own attributes
mutable struct PlasmoEdge <: AbstractPlasmoEdge
    # index::Dict{AbstractPlasmoGraph,LightGraphs.Edge}
    indices::Dict{AbstractPlasmoGraph,Pair}  #index in each graph
    #label::Symbol
    #attributes::Dict
    #model::AbstractModel
    #link_data::LinkData
    link_data::LinkData
end
#Edge constructors
PlasmoEdge() = PlasmoEdge(Dict{AbstractPlasmoGraph,Pair}(),LinkData())
create_edge() = PlasmoEdge()

function PlasmoEdge(g::AbstractPlasmoGraph,edge::Pair)
    add_edge!(g.graph,edge)  #Add the edge to the lightgraph
    #label = Symbol("edge"*string(edge))
    #pedge = PlasmoEdge(Dict(g => edge),label,Dict(),Model(),LinkData())
    pedge = PlasmoEdge(Dict(g => edge),LinkData())
    g.edge_dict[pedge] = edge
    #g.edges[edge] = pedge
    return pedge
end

# #TODO I think this is also for copying?
# function add_edge!(g::AbstractPlasmoGraph,pedge::AbstractPlasmoEdge,src::AbstractPlasmoNode,dst::AbstractPlasmoNode)
#     edge = LightGraphs.Edge(src.indices[g],dst.indices[g])
#     add_edge!(g.graph,edge)
#     #label = Symbol("edge"*string(edge))
#     pedge.indices[g] = edge
#     push!(g.edge_dict,edge)
#     #g.edges[edge] = pedge
#     return pedge
# end

add_edge!(g::AbstractPlasmoGraph,edge::Pair) = PlasmoEdge(g,edge)
add_edge!(g::AbstractPlasmoGraph,src::Int,dst::Int) = PlasmoEdge(g,LightGraphs.Edge(src,dst))
add_edge!(g::AbstractPlasmoGraph,src::AbstractNode,dst::AbstractNode) = PlasmoEdge(g,LightGraphs.Edge(src.index[g],dst.index[g]))
#Pair
#Tuple



#Setting and getting Graph Properties
getnodes(g::AbstractPlasmoGraph) = g.nodes  #dictionary
getedges(g::AbstractPlasmoGraph) = g.edges  #dictionary
getsubgraphlist(g::PlasmoGraph) = g.subgraphlist
getnode(g::AbstractPlasmoGraph,i::Int) = g.nodes[i]
getedge(g::AbstractPlasmoGraph,edge::LightGraphs.Edge) = g.edges[edge]
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
src(pgraph::AbstractPlasmoGraph,edge::AbstractPlasmoEdge) = getnode(pgraph,LightGraphs.src(edge.index[pgraph]))  #source node of a Plasmo Edge
dst(pgraph::AbstractPlasmoGraph,edge::AbstractPlasmoEdge) = getnode(pgraph,LightGraphs.dst(edge.index[pgraph]))  #destination node of a Plasmo Edge
src(pgraph::AbstractPlasmoGraph,edge::AbstractEdge) = getnode(pgraph,LightGraphs.src(edge))  #source node of a Plasmo Edge
dst(pgraph::AbstractPlasmoGraph,edge::AbstractEdge) = getnode(pgraph,LightGraphs.dst(edge))  #destination node of a Plasmo Edge

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

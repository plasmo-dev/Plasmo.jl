import LightGraphs:AbstractGraph,Graph,DiGraph,add_vertex!,add_edge!,nv,ne,vertices,edges,in_neighbors,out_neighbors,in_edges,out_edges,src,dst,degree
import Base:show,print,string,getindex,copy
import LightGraphs
import JuMP:Model,UnsetSolver,setsolver,getobjectivevalue
import MathProgBase.SolverInterface:AbstractMathProgSolver

##############################################################################
# Graphs
##############################################################################
#A PlasmoGraph encapsulates a pure graph object wherein nodes and edges are integers and pairs of integers respectively
"The PlasmoGraph Type.  Contains a reference to a LightGraphs.Graph "
type PlasmoGraph <: AbstractPlasmoGraph
    graph::AbstractGraph            #A lightgraph!
    label::Symbol
    index::Integer  #The index of this graph within a higher level graph (i.e. its index in another graph's subgraphlist) 0 means it isn't a subgraph
    subgraphlist::Vector{AbstractPlasmoGraph}   #How plasmo manages structure
    attributes::Dict{Any,Any}                   #e.g. LinkData; might make primary attributes (like models) into actual fields
    nodes::Dict{Int,AbstractNode}               #Includes nodes in the subgraphs as well
    edges::Dict{LightGraphs.Edge,AbstractEdge}  #Includes edges in the subgraphs as well
    #nodemap::Dict{Symbol,AbstractNode}         #I'm thinking about also including node and edge maps to reference nodes and edges by a symbol
    #edgemap::Dict{Symbol,AbstractNode}
    solver::AbstractMathProgSolver #for solve(graph)
    objVal::Number
end

"""
PlasmoGraph()

Creates an empty PlasmoGraph
"""
PlasmoGraph() = PlasmoGraph(DiGraph(),gensym(),0,AbstractGraph[],Dict(:LinkData => GraphLinkData()),Dict{Int,AbstractNode}(),Dict{LightGraphs.Edge,AbstractEdge}(),UnsetSolver(),NaN)
const GraphModel = PlasmoGraph

"""
PlasmoGraph(::AbstractGraph)

Creates a PlasmoGraph given a LightGraph object
"""
function PlasmoGraph(g::AbstractGraph)  #build a graph from a LightGraph
    pgraph = PlasmoGraph(g,gensym(),0,AbstractGraph[],Dict(:LinkData => GraphLinkData()),Dict{Int,AbstractNode}(),Dict{LightGraphs.Edge,AbstractEdge}(),UnsetSolver(),NaN)
    for vertex in vertices(g)
        pgraph.nodes[vertex] = PlasmoNode(Dict(pgraph => vertex),Symbol("node"*string(vertex)),Dict())
    end
    for edge in edges(g)
        pgraph.edges[edge] = PlasmoEdge(Dict(pgraph => edge),Symbol("edge"*string(edge)),Dict())
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
##############################################################################
# Nodes
##############################################################################
#Nodes and edges are integers and pairs.  When adding nodes, it creates the plasmo node data structure and also adds the vertex to the underlying lightgraph
#A Plasmo Node maps to a PlasmoGraph.  It holds an index to its integer in the underlying graph and holds its own attributes.
type PlasmoNode <: AbstractNode
    index::Dict{PlasmoGraph,Int} #map to an index in each graph containing the node
    label::Symbol
    attributes::Dict{Any,Any}  #A model is an attribute
end

# Node constructors
PlasmoNode() = PlasmoNode(Dict{PlasmoGraph,Int}(), Symbol("node"),Dict{Any,Any}(:model => Model(),:LinkData => NodeLinkData()))
function PlasmoNode(g::PlasmoGraph)
    add_vertex!(g.graph)
    i = nv(g.graph)
    label = Symbol("node"*string(i))
    node = PlasmoNode(Dict(g => i),label,Dict(:model => Model(),:LinkData => NodeLinkData()))
    g.nodes[i] = node
    return node
end

#Add an existing node to a graph.  It's possible to pass a user specified index.  This is useful for copying graphs
function add_node!(g::PlasmoGraph,node::PlasmoNode;index = nv(g.graph)+1)
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
    index::Dict{PlasmoGraph,LightGraphs.Edge}
    label::Symbol
    attributes::Dict
end
#Edge constructors
PlasmoEdge() = PlasmoEdge(Dict{PlasmoGraph,LightGraphs.Edge}(), Symbol("edge"),Dict{Any,Any}(:model => Model(),:LinkData => NodeLinkData()))
function PlasmoEdge(g::PlasmoGraph,edge::LightGraphs.Edge)
    add_edge!(g.graph,edge)
    label = Symbol("edge"*string(edge))
    pedge = PlasmoEdge(Dict(g => edge),label,Dict(:model => Model(),:LinkData => NodeLinkData()))
    g.edges[edge] = pedge
    return pedge
end

function add_edge!(g::PlasmoGraph,pedge::PlasmoEdge,src::PlasmoNode,dst::PlasmoNode)
    edge = LightGraphs.Edge(src.index[g],dst.index[g])
    add_edge!(g.graph,edge)
    label = Symbol("edge"*string(edge))
    pedge.index[g] = edge
    g.edges[edge] = pedge
    return pedge
end
add_edge!(g::PlasmoGraph,edge::LightGraphs.Edge) = PlasmoEdge(g,edge)
add_edge!(g::PlasmoGraph,src::Int,dst::Int) = PlasmoEdge(g,LightGraphs.Edge(src,dst))
add_edge!(g::PlasmoGraph,src::PlasmoNode,dst::PlasmoNode) = PlasmoEdge(g,LightGraphs.Edge(src.index[g],dst.index[g]))



#Setting and getting Graph Properties
getnodes(g::PlasmoGraph) = g.nodes  #dictionary
getedges(g::PlasmoGraph) = g.edges  #dictionary
getsubgraphlist(g::PlasmoGraph) = g.subgraphlist
getnode(g::PlasmoGraph,i::Int) = g.nodes[i]
getedge(g::PlasmoGraph,edge::LightGraphs.Edge) = g.edges[edge]
function getnodesandedges(g::PlasmoGraph)
    d = Dict{Union{Int,LightGraphs.Edge},NodeOrEdge}()
    merge!(d,getnodes(g))
    merge!(d,getedges(g))
    return d
end
getnodeoredge(g::PlasmoGraph,i::Union{Int,LightGraphs.Edge}) = isa(i,Int)? getnode(g,i): getedge(g,i)


getnodeindex(g::PlasmoGraph,node::PlasmoNode) = node.index[g]
getedgeindex(g::PlasmoGraph,edge::PlasmoEdge) = edge.index[g]

"""
    getindex(::PlasmoGraph,::NodeOrEdge)
    Get the index of a node or edge within a PlasmoGraph
"""
getindex(g::PlasmoGraph,nodeoredge::NodeOrEdge) = nodeoredge.index[g]
"""
    getindex(::PlasmoGraph,::NodeOrEdge)
    Return a dictionary of a node's or edge's index in each of its graphs.
"""
getindex(nodeoredge::NodeOrEdge) = nodeoredge.index

#Print Functions
string(graph::PlasmoGraph) = "plasmo graph: "*string(graph.label)*"\n"*string(graph.graph)
print(io::IO, graph::PlasmoGraph) = print(io, string(graph))
show(io::IO,graph::PlasmoGraph) = print(io,graph)

string(node::PlasmoNode) = "plasmo node: "*string(node.label)*string(node.index)
print(io::IO,node::PlasmoNode) = print(io, string(node))
show(io::IO,node::PlasmoNode) = print(io,node)

string(edge::PlasmoEdge) = "plasmo edge: "*string(edge.label)
print(io::IO,edge::PlasmoEdge) = print(io, string(edge))
show(io::IO,edge::PlasmoEdge) = print(io,edge)

##############################################################################
# Attributes
##############################################################################
#add or remove attributes from graphs, nodes, and edges
function addattribute!(graph::PlasmoGraph,attribute::Symbol,value)
    graph.attributes[attribute] = value
end
function addattribute!(item::NodeOrEdge,attribute::Symbol,value)
    item.attributes[attribute] = value
end
function addattribute!(g::PlasmoGraph,i::Int,attribute::Symbol,value)
    node = g.nodes[i]
    addattribute!(node,attribute,value)
end
function addattribute!(g::PlasmoGraph,edge::LightGraphs.Edge,attribute::Symbol,value)
    pedge = g.edges[edge]
    addattribute!(pedge,attribute,value)
end
getattribute(item::NodeOrEdge,attribute::Symbol) = item.attributes[attribute]
hasattribute(item::NodeOrEdge,attribute::Symbol) = haskey(item.attributes,attribute)

rmattribute!(item::NodeOrEdge,attribute::Symbol) = delete!(item.attributes,attribute)
rmattribute!(graph::PlasmoGraph,attribute::Symbol) = delete!(graph.attributes,attribute)

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
function _copy_subgraphs!(graph1::PlasmoGraph,graph2::PlasmoGraph)
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
src(pgraph::PlasmoGraph,edge::PlasmoEdge) = getnode(pgraph,LightGraphs.src(edge.index[pgraph]))  #source node of a Plasmo Edge
dst(pgraph::PlasmoGraph,edge::PlasmoEdge) = getnode(pgraph,LightGraphs.dst(edge.index[pgraph]))  #destination node of a Plasmo Edge
src(pgraph::PlasmoGraph,edge::LightGraphs.Edge) = getnode(pgraph,LightGraphs.src(edge))  #source node of a Plasmo Edge
dst(pgraph::PlasmoGraph,edge::LightGraphs.Edge) = getnode(pgraph,LightGraphs.dst(edge))  #destination node of a Plasmo Edge

in_edges(pgraph::PlasmoGraph,node::PlasmoNode) = [pgraph.edges[LightGraphs.Edge(in_node,getindex(pgraph,node))] for in_node in LightGraphs.in_neighbors(pgraph.graph,getindex(pgraph,node))]
out_edges(pgraph::PlasmoGraph,node::PlasmoNode) = [pgraph.edges[LightGraphs.Edge(getindex(pgraph,node),out_node)] for out_node in LightGraphs.out_neighbors(pgraph.graph,getindex(pgraph,node))]

in_neighbors(pgraph::PlasmoGraph,node::PlasmoNode) = [pgraph.nodes[node] for node in LightGraphs.in_neighbors(pgraph.graph,getindex(pgraph,node))]
out_neighbors(pgraph::PlasmoGraph,node::PlasmoNode) = [pgraph.nodes[node] for node in LightGraphs.out_neighbors(pgraph.graph,getindex(pgraph,node))]
neighbors(pgraph::PlasmoGraph,node::PlasmoNode) = [pgraph.nodes[node] for node in LightGraphs.all_neighbors(pgraph.graph,getindex(pgraph,node))]


getsupportingedges(pgraph::PlasmoGraph,node::PlasmoNode) = [in_edges(pgraph,node);out_edges(pgraph,node)]

getconnectedfrom(pgraph::PlasmoGraph,edge::PlasmoEdge) = src(pgraph,edge)
getconnectedto(pgraph::PlasmoGraph,edge::PlasmoEdge) = dst(pgraph,edge)
getsupportingnodes(pgraph::PlasmoGraph,edge::PlasmoEdge) = tuple(src(pgraph,edge),dst(pgraph,edge))
getsupportingnodes(pgraph::PlasmoGraph,edge::LightGraphs.Edge) = tuple(src(pgraph,edge),dst(pgraph,edge))

degree(pgraph::PlasmoGraph,node::PlasmoNode) = degree(pgraph.graph,node.index[pgraph])
in_degree(pgraph::PlasmoGraph,node::PlasmoNode) = length(in_neighbors(pgraph::PlasmoGraph,node::PlasmoNode))
out_degree(pgraph::PlasmoGraph,node::PlasmoNode) = length(out_neighbors(pgraph::PlasmoGraph,node::PlasmoNode))

is_connected(graph::PlasmoGraph,n1::PlasmoNode,n2::PlasmoNode)  = n2 in neighbors(graph,n1)
is_connected(graph::PlasmoGraph,node::PlasmoNode,edge::PlasmoEdge)  = edge in getsupportingedges(graph,node)
is_connected(graph::PlasmoGraph,edge::PlasmoEdge,node::PlasmoNode)  = edge in getsupportingedges(graph,node)
is_connected(graph::PlasmoGraph,edge1::PlasmoEdge,edge2::PlasmoEdge)  = !isempty(intersect(getsupportingnodes(graph,edge1),getsupportingnodes(graph,edge2)))

##########################################
# Other useful functions
##########################################
"""
    contains_node(g::PlasmoGraph,n::NodeOrEdge)
    return whether a PlasmoGraph:g, contains the given node or edge: n
"""
contains_node(graph::PlasmoGraph,nodeoredge::NodeOrEdge) = nodeoredge in [graph.nodes;graph.edges]
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

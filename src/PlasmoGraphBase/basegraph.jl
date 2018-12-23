##############################################################################
# Base Plasmo Graph Structures
##############################################################################
"""
BasePlasmoGraph()

The BasePlasmoGraph Type.  The BasePlasmoGraph wraps a LightGraphs.AbstractGraph (such as a LightGraphs.Graph or LightGraphs.DiGraph).
The BasePlasmoGraph extends a LightGraphs.AbstractGraph and adds a label (i.e. a name), an index, attributes (a dictionary), and a nodedict and edgedict to map nodes and edges to indices.
Most notable is the addition of a subgraphlist.  A BasePlasmoGraph contains a list of other AbstractPlasmoGraph objects reprsenting subgraphs within the BasePlasmoGraph.  The index therefore, is the
PlasmoGraph index within its parent graph.  An index of 0 means the graph is the top-level graph (i.e. it is not a subgraph of any other graph).
"""
mutable struct BasePlasmoGraph{T <: AbstractGraph} <: AbstractPlasmoGraph
    lightgraph::T                               #The underlying lightgraph  #Could be a Graph or DiGraph, #or a custom hypergraph
    label::Symbol
    index::Integer                              #The index of this graph within a higher level graph (i.e. its index in another graph's subgraphlist) 0 means it isn't a subgraph
    subgraphlist::Vector{AbstractPlasmoGraph}   #How Plasmo manages structure
    nodedict::NodeDict                          #Includes nodes in the subgraphs as well
    edgedict::EdgeDict                          #Includes edges in the subgraphs as well
    attributes::Dict
end
#Constructors
BasePlasmoGraph() = BasePlasmoGraph(LightGraphs.Graph(),gensym(),0,AbstractPlasmoGraph[],NodeDict(),EdgeDict(),Dict())
BasePlasmoGraph(graphtype) = BasePlasmoGraph(graphtype(),gensym(),0,AbstractPlasmoGraph[],NodeDict(),EdgeDict(),Dict())

function BasePlasmoGraph(lightgraph::LightGraphs.AbstractGraph)  #build a graph from a LightGraph
    basegraph = BasePlasmoGraph(lightgraph,gensym(),0,AbstractPlasmoGraph[],NodeDict(),EdgeDict(),Dict())
    for vertex in LightGraphs.vertices(lightgraph)
        add_node!(basegraph)
    end
    for edge in LightGraphs.edges(lightgraph) #these are LightGraph.AbstractEdge(s)...
        add_edge!(basegraph,edge)
    end
    return basegraph
end

"The BasePlasmoNode Type.  Contains indices corresponding to each graph it is a member of as well as an attribute dictionary."
mutable struct BasePlasmoNode <: AbstractPlasmoNode
    indices::Dict{BasePlasmoGraph,Int} #map to an index in each graph containing the node
    label::Symbol
    attributes::Dict
end
#Constructors
BasePlasmoNode() = BasePlasmoNode(Dict{BasePlasmoGraph,Int}(),Symbol("basenode"),Dict{Symbol,Any}())
create_node(graph::BasePlasmoGraph) = BasePlasmoNode()

"The BasePlasmoEdge Type.  Can be indexed to multiple BasePlasmoGraphs.  Can also be referenced by an edge id."
mutable struct BasePlasmoEdge <: AbstractPlasmoEdge
    indices::Dict{BasePlasmoGraph,LightGraphs.AbstractEdge} #map to an index in each graph containing the node
    edge_id::Dict{BasePlasmoGraph,Int}
    label::Symbol
end
#Constructors
BasePlasmoEdge() = BasePlasmoEdge(Dict{BasePlasmoGraph,LightGraphs.AbstractEdge}(),Dict{BasePlasmoGraph,Int}(),Symbol("baseedge"))
create_edge(graph::BasePlasmoGraph) = BasePlasmoEdge()

##############################################################################
# Base Plasmo Graph
##############################################################################
getbasegraph(graph::BasePlasmoGraph) = graph
getlightgraph(basegraph::BasePlasmoGraph) = basegraph.lightgraph
"""
getindex(basegraph::BasePlasmoGraph)

Get a basegraph index
"""
getindex(basegraph::BasePlasmoGraph) = basegraph.index
getlabel(basegraph::BasePlasmoGraph) = basegraph.label

getsubgraphlist(basegraph::BasePlasmoGraph) = basegraph.subgraphlist
getsubgraph(basegraph::BasePlasmoGraph,index::Int) = basegraph.subgraphlist[index]

getnodes(basegraph::BasePlasmoGraph) = nodes(basegraph.nodedict)
getedges(basegraph::BasePlasmoGraph) = edges(basegraph.edgedict)

getnode(basegraph::BasePlasmoGraph,index::Int) = basegraph.nodedict[index]
getedge(basegraph::BasePlasmoGraph,edge::LightGraphs.AbstractEdge) = basegraph.edgedict[edge]

#TODO Make this more general for hypergraphs
#getedge(basegraph::BasePlasmoGraph,from::Int,to::Int) = basegraph.edgedict[SimpleEdge(from,to)]
getedge(basegraph::BasePlasmoGraph,from::Int,to::Int) = basegraph.edgedict[edgetype(basegraph.lightgraph)(from,to)]
getedge(basegraph::BasePlasmoGraph,vertices::Int...) = basegraph.edgedict[edgetype(basegraph.lightgraph)(vertices...)]

has_edge(basegraph::BasePlasmoGraph,from::Int,to::Int) = haskey(basegraph.edgedict.id_dict,edgetype(basegraph.lightgraph)(from,to))
has_edge(basegraph::BasePlasmoGraph,vertices::Int...) = haskey(basegraph.edgedict.id_dict,edgetype(basegraph.lightgraph)(vertices...))
##############################################################################
# Base Nodes
##############################################################################
#base node has index and label fields
getbasenode(basenode::BasePlasmoNode) = basenode
"""
getindex(basegraph::BasePlasmoGraph,basenode::BasePlasmoNode)

Get the index of the node in the BasePlasmoGraph
"""
getindex(basegraph::BasePlasmoGraph,basenode::BasePlasmoNode) = basenode.indices[basegraph]
getindices(basenode::BasePlasmoNode) = basenode.indices
getlabel(basenode::BasePlasmoNode) = basenode.label

###############################################################################
# Base Edges
###############################################################################
getbaseedge(baseedge::BasePlasmoEdge) = baseedge
getindex(basegraph::BasePlasmoGraph,baseedge::BasePlasmoEdge) = baseedge.indices[basegraph]
getindices(baseedge::BasePlasmoEdge) = baseedge.indices
getlabel(baseedge::BasePlasmoEdge) = baseedge.label

##############################################################################
#Topology functions (LightGraphs extensions)
##############################################################################
src(basegraph::BasePlasmoGraph,baseedge::BasePlasmoEdge) = getnode(basegraph,LightGraphs.src(getindex(basegraph,baseedge)))  #source node of a Plasmo Edge
dst(basegraph::BasePlasmoGraph,baseedge::BasePlasmoEdge) = getnode(basegraph,LightGraphs.dst(getindex(basegraph,baseedge)))  #destination node of a Plasmo Edge
src(basegraph::BasePlasmoGraph,edge::LightGraphs.AbstractEdge) = getnode(basegraph,LightGraphs.src(edge))  #source node of a Plasmo Edge
dst(basegraph::BasePlasmoGraph,edge::LightGraphs.AbstractEdge) = getnode(basegraph,LightGraphs.dst(edge))  #destination node of a Plasmo Edge

#New stuff
in_edges(basegraph::BasePlasmoGraph,node::BasePlasmoNode) = [getedge(basegraph,in_node,getindex(basegraph,node)) for in_node in LightGraphs.inneighbors(getlightgraph(basegraph),getindex(basegraph,node))]
out_edges(basegraph::BasePlasmoGraph,node::BasePlasmoNode) = [getedge(basegraph,getindex(basegraph,node),out_node) for out_node in LightGraphs.outneighbors(getlightgraph(basegraph),getindex(basegraph,node))]


in_neighbors(basegraph::BasePlasmoGraph,node::BasePlasmoNode) = [getnode(basegraph,node_index) for node_index in LightGraphs.inneighbors(getlightgraph(basegraph),getindex(basegraph,node))]
out_neighbors(basegraph::BasePlasmoGraph,node::BasePlasmoNode) = [getnode(basegraph,node_index) for node_index in LightGraphs.outneighbors(getlightgraph(basegraph),getindex(basegraph,node))]
neighbors(basegraph::BasePlasmoGraph,node::BasePlasmoNode) = [getnode(basegraph,node_index) for node_index in LightGraphs.all_neighbors(getlightgraph(basegraph),getindex(basegraph,node))]

#NOTE Make this function more general
function getsupportingedges(basegraph::BasePlasmoGraph,node::BasePlasmoNode)
    if isa(basegraph.lightgraph,HyperGraph)
        return basegraph.lightgraph.node_map[getindex(basegraph,node)]
    elseif isa(basegraph.lightgraph,Graph)
        neighbors = LightGraphs.all_neighbors(getlightgraph(basegraph),getindex(basegraph,node))
        index = getindex(basegraph,node)
        edges = []
        for neigh in neighbors
            if neigh > index
                push!(edges,getedge(basegraph,getindex(basegraph,node),neigh))
            else
                push!(edges,getedge(basegraph,neigh,getindex(basegraph,node)))
            end
        end

        return [getedge(basegraph,getindex(basegraph,node),neighbor) for neighbor in LightGraphs.all_neighbors(getlightgraph(basegraph),getindex(basegraph,node))]
    else
        #return [getedge(basegraph,getindex(basegraph,node),neighbor) for neighbor in LightGraphs.all_neighbors(getlightgraph(basegraph),getindex(basegraph,node))]
        return [in_edges(basegraph,node);out_edges(basegraph,node)]
    end
end

function getsupportingnodes(basegraph::BasePlasmoGraph,edge::BasePlasmoEdge)
    if isa(basegraph.lightgraph,HyperGraph)
        vertices = edge.indices[basegraph].vertices
        return [getnode(basegraph,vertex) for vertex in vertices]
    else
        return [src(basegraph,edge),dst(basegraph,edge)]
    end
end

#getsupportingnodes(basegraph::BasePlasmoGraph,edge::BasePlasmoEdge) = tuple(src(basegraph,edge),dst(basegraph,edge))


getconnectedfrom(basegraph::BasePlasmoGraph,edge::BasePlasmoEdge) = src(basegraph,edge)
getconnectedto(basegraph::BasePlasmoGraph,edge::BasePlasmoEdge) = dst(basegraph,edge)

degree(basegraph::BasePlasmoGraph,node::BasePlasmoNode) = LightGraphs.degree(getlightgraph(basegraph),getindex(basegraph,node))
in_degree(basegraph::BasePlasmoGraph,node::BasePlasmoNode) = length(in_neighbors(basegraph,node))
out_degree(basegraph::BasePlasmoGraph,node::BasePlasmoNode) = length(out_neighbors(basegraph,node))

is_connected(basegraph::BasePlasmoGraph,n1::BasePlasmoNode,n2::BasePlasmoNode)  = n2 in neighbors(basegraph,n1)
is_connected(basegraph::BasePlasmoGraph,node::BasePlasmoNode,edge::LightGraphs.AbstractEdge)  = edge in getsupportingedges(basegraph,node)
is_connected(basegraph::BasePlasmoGraph,edge::BasePlasmoEdge,node::BasePlasmoNode)  = edge in getsupportingedges(basegraph,node)
is_connected(basegraph::BasePlasmoGraph,edge1::BasePlasmoEdge,edge2::BasePlasmoEdge)  = !isempty(intersect(getsupportingnodes(basegraph,edge1),getsupportingnodes(basegraph,edge2)))


#####################################
# Copy function
#####################################
function copy(basegraph::BasePlasmoGraph)

    new_base_graph = BasePlasmoGraph(typeof(basegraph.lightgraph)())

    #Now add subgraphs
    for i = 1:length(getsubgraphlist(basegraph))
        subgraph = BasePlasmoGraph(typeof(basegraph.lightgraph)())
        add_subgraph!(new_base_graph,subgraph)
    end

    #Add nodes
    for node in getnodes(basegraph)
        #set index in top level graph
        node_index = getindex(basegraph,node)
        new_node = BasePlasmoNode()
        add_node!(new_base_graph,new_node,index = node_index)  #add node to new graph

        #Get the other subgraphs this node is in
        subgraphs = collect(keys(getindices(node)))  #all graphs this node is in
        for subgraph in subgraphs
            subgraph_index = getindex(subgraph)
            if subgraph_index != 0  #already added to this one
                #Add to the subgraph
                new_subgraph = getsubgraph(new_base_graph,subgraph_index)
                node_index = getindex(subgraph,node)
                add_node!(new_subgraph,new_node,index = node_index)
            end
        end
    end

    #Add edges to each graph
    for edge in getedges(basegraph)
        edge_index = getindex(basegraph,edge)
        add_edge!(new_base_graph,edge_index)

        for subgraph in getsubgraphlist(basegraph)
                subgraph_index = getindex(subgraph)
                for edge in getedges(subgraph)
                    edge_index = getindex(subgraph,edge)
                    new_subgraph = getsubgraph(new_base_graph,subgraph_index)
                    add_edge!(new_subgraph,edge_index)
                end
        end
    end
    return new_base_graph
end















#

##############################################################################
# Define the PlasmoGraph Interface for graphs with subgraph lists, nodes, and edges
##############################################################################
###############################
# Graph Interface
###############################
getbasegraph(graph::AbstractPlasmoGraph) = graph.basegraph
getlightgraph(graph::AbstractPlasmoGraph) = getlightgraph(getbasegraph(graph))

getindex(graph::AbstractPlasmoGraph) = getindex(getbasegraph(graph))
getlabel(graph::AbstractPlasmoGraph) = getlabel(getbasegraph(graph))

getsubgraphlist(graph::AbstractPlasmoGraph) = getsubgraphlist(graph.basegraph)
getsubgraph(graph::AbstractPlasmoGraph,index::Int) = getsubgraph(graph.basegraph,index)

getnodes(graph::AbstractPlasmoGraph) = getnodes(getbasegraph(graph))
getedges(graph::AbstractPlasmoGraph) = getedges(getbasegraph(graph))
collectnodes(graph::AbstractPlasmoGraph) = collect(getnodes(graph))
collectedges(graph::AbstractPlasmoGraph) = collect(getedges(graph))

getnode(graph::AbstractPlasmoGraph,index::Int) = getnode(getbasegraph(graph),index)
getedge(graph::AbstractPlasmoGraph,src::Int,dst::Int) = getedge(getbasegraph(graph),src,dst)
getedge(graph::AbstractPlasmoGraph,edge::LightGraphs.AbstractEdge) = getedge(getbasegraph(graph),edge)
getedge(graph::AbstractPlasmoGraph,pair::Pair) = getedge(getbasegraph(graph),pair)
getedge(graph::AbstractPlasmoGraph,tuple::Tuple) = getedge(getbasegraph(graph,tuple))

has_edge(graph::AbstractPlasmoGraph,src::Int,dst::Int) = has_edge(getbasegraph(graph),src,dst)

##############################
# Node Interface
##############################
create_node(graph::AbstractPlasmoGraph) = error("create_node function not defined for $(typeof(graph))")
getbasenode(node::AbstractPlasmoNode) = node.basenode
getindices(node::AbstractPlasmoNode) = getindices(node.basenode)
getlabel(node::AbstractPlasmoNode) = getlabel(node.basenode)
getindex(graph::AbstractPlasmoGraph,node::AbstractPlasmoNode) = getindex(getbasegraph(graph),getbasenode(node))

function add_node!(graph::AbstractPlasmoGraph)
    basegraph = getbasegraph(graph)
    LightGraphs.add_vertex!(basegraph.lightgraph)
    index = LightGraphs.nv(basegraph.lightgraph)
    label = Symbol("node"*string(index))

    node = create_node(graph)                   #create a node for the given graph type
    basenode = getbasenode(node)
    basenode.indices[basegraph] = index             #Set the index of this node in this basegraph
    add_node!(basegraph.nodedict,node,index)
    return node
end

#Add an existing node to a graph.  It's possible to pass a user specified index.  This is useful for copying graphs
function add_node!(graph::AbstractPlasmoGraph,node::AbstractPlasmoNode;index = LightGraphs.nv(getlightgraph(graph))+1)
    basegraph = getbasegraph(graph)
    LightGraphs.add_vertex!(getlightgraph(basegraph))                #add the light graph vertex
    basenode = getbasenode(node)
    basenode.indices[basegraph] = index
    add_node!(basegraph.nodedict,node,index)                         #add the node at the given index
    return basenode
end

###############################
# Edge Interface
###############################
create_edge(graph::AbstractPlasmoGraph) = error("create_edge function not defined for $(typeof(graph))")
getbaseedge(edge::AbstractPlasmoEdge) = edge.baseedge
getindices(edge::AbstractPlasmoEdge) = getindices(edge.baseedge)
getlabel(edge::AbstractPlasmoEdge) = getlabel(edge.baseedge)
getindex(graph::AbstractPlasmoGraph,edge::AbstractPlasmoEdge) = getindex(getbasegraph(graph),getbaseedge(edge))

function add_edge!(graph::AbstractPlasmoGraph,lightedge::LightGraphs.AbstractEdge{Int})
    basegraph = getbasegraph(graph)
    added = LightGraphs.add_edge!(getlightgraph(graph),lightedge)  #add the edge to the lightgraph
    if added
        lightedge = edgetype(getlightgraph(graph))(lightedge)
        edge = create_edge(graph)                               #create edge for this graph type
        add_edge!(basegraph.edgedict,edge,lightedge)            #add to the edge dictionary
        baseedge = getbaseedge(edge)
        baseedge.indices[basegraph] = lightedge                 #set the edge index in the basegraph
        edge_id = length(basegraph.edgedict)                    #give it an integer id
        baseedge.edge_id[basegraph] = edge_id                   #set the edge id in the graph
        return edge
    else
        lightedge = edgetype(getlightgraph(graph))(lightedge)
        edge = getedge(graph,lightedge)
        return edge
    end
end

#Add an existing base edge to a base graph
function add_edge!(graph::AbstractPlasmoGraph,edge::AbstractPlasmoEdge,src::AbstractPlasmoNode,dst::AbstractPlasmoNode)
    basegraph = getbasegraph(graph)
    lightedge = SimpleEdge(getindex(graph,src),getindex(graph,dst))
    add_edge!(basegraph.edge_dict,edge,lightedge)       #add to the edge dictionary
    baseedge = getbaseedge(edge)
    baseedge.indices[basegraph] = lightedge
    edge_id = length(basegraph.edgedict)
    baseedge.edge_id[basegraph] = edge_id
    return edge
end

add_edge!(graph::AbstractPlasmoGraph,src::Int,dst::Int) = add_edge!(graph,SimpleEdge(src,dst))
add_edge!(graph::AbstractPlasmoGraph,src::AbstractPlasmoNode,dst::AbstractPlasmoNode) = add_edge!(graph,SimpleEdge(getindex(graph,src),getindex(graph,dst)))
add_edge!(graph::AbstractPlasmoGraph,pair::Pair) = add_edge!(graph,SimpleEdge(pair.first.pair.second))

add_edge!(graph::AbstractPlasmoGraph,vertices::Int...) = add_edge!(graph,HyperEdge(vertices...))

#Add hyper edge using node references
function add_edge!(graph::AbstractPlasmoGraph,nodes::AbstractPlasmoNode...)
    indices = [getindex(graph,node) for node in nodes]
    edge = add_edge!(graph,HyperEdge(indices...))
    return edge
end

##############################################################################
# Subgraphs
##############################################################################
#Managing subgraphs
#Add nodes, but don't add edges.  neighbors, degree, etc... are graph specific
function add_subgraph!(graph::AbstractPlasmoGraph,subgraph::AbstractPlasmoGraph)
    push!(getbasegraph(graph).subgraphlist,subgraph)
    getbasegraph(subgraph).index = length(getsubgraphlist(graph))
    for node in getnodes(subgraph)
        add_node!(graph,node)  #nodes get added at new indices for graph
    end
    #NOTE It makes more sense not to include the edges from the subgraph in the higher level graph.  This makes it easier to manage hierarchies.
    # for edge in getedges(subgraph)
    #     from_node_sub = getconnectedfrom(subgraph,edge)
    #     to_node_sub = getconnectedto(subgraph,edge)
    #     add_edge!(graph,from_node_sub,to_node_sub)
    # end
    return graph
end

#Topology functions (LightGraphs extensions)
src(graph::AbstractPlasmoGraph,edge::AbstractPlasmoEdge) = src(graph.basegraph,edge.baseedge)           #source node of a Plasmo Edge
dst(graph::AbstractPlasmoGraph,baseedge::AbstractPlasmoEdge) = dst(graph.basegraph,edge.baseedge)       #destination node of a Plasmo Edge
src(graph::AbstractPlasmoGraph,edge::LightGraphs.AbstractEdge) = src(graph.basegraph,LightGraphs.src(edge.baseedge))  #source node of a Plasmo Edge
dst(graph::AbstractPlasmoGraph,edge::LightGraphs.AbstractEdge) = dst(graph.basegraph,LightGraphs.dst(edge.baseedge))  #destination node of a Plasmo Edge

#New stuff
in_edges(graph::AbstractPlasmoGraph,node::AbstractPlasmoNode) = in_edges(graph.basegraph,node.basenode)
out_edges(graph::AbstractPlasmoGraph,node::AbstractPlasmoNode) = out_edges(graph.basegraph,node.basenode)

in_neighbors(graph::AbstractPlasmoGraph,node::AbstractPlasmoNode) = in_neighbors(graph.basegraph,node.basenode)
out_neighbors(graph::AbstractPlasmoGraph,node::AbstractPlasmoNode) = out_neighbors(graph.basegraph,node.basenode)
neighbors(graph::AbstractPlasmoGraph,node::AbstractPlasmoNode) = neighbors(graph.basegraph,node.basenode)

getsupportingedges(graph::AbstractPlasmoGraph,node::AbstractPlasmoNode) = getsupportingedges(graph.basegraph,node.basenode)
getconnectedfrom(graph::AbstractPlasmoGraph,edge::AbstractPlasmoEdge) = getconnectedfrom(graph.basegraph,edge.baseedge)
getconnectedto(graph::AbstractPlasmoGraph,edge::AbstractPlasmoEdge) = getconnectedto(graph.basegraph,edge.baseedge)
getsupportingnodes(graph::AbstractPlasmoGraph,edge::AbstractPlasmoEdge) = tuple(src(graph.basegraph,edge),dst(graph.basegraph,edge))

#has_edge(graph::AbstractPlasmoGraph,edge::AbstractPlasmoEdge) = LightGraphs.has_edge(getlightgraph(graph.basegraph),getindex(graph.basegraph,edge.baseedge))

degree(graph::AbstractPlasmoGraph,node::AbstractPlasmoNode) = LightGraphs.degree(getlightgraph(graph.basegraph),getindex(graph.basegraph,node.basenode))
in_degree(graph::AbstractPlasmoGraph,node::AbstractPlasmoNode) = length(in_neighbors(graph.basegraph,node.basenode))
out_degree(graph::AbstractPlasmoGraph,node::AbstractPlasmoNode) = length(out_neighbors(graph.basegraph,node.basenode))

is_connected(basegraph::AbstractPlasmoGraph,n1::AbstractPlasmoNode,n2::AbstractPlasmoNode)  = n2 in neighbors(basegraph,n1)
is_connected(basegraph::AbstractPlasmoGraph,node::AbstractPlasmoNode,edge::AbstractEdge)  = edge in getsupportingedges(basegraph,node)
is_connected(basegraph::AbstractPlasmoGraph,edge::AbstractPlasmoEdge,node::AbstractPlasmoNode)  = edge in getsupportingedges(basegraph,node)
is_connected(basegraph::AbstractPlasmoGraph,edge1::AbstractPlasmoEdge,edge2::AbstractPlasmoEdge)  = !isempty(intersect(getsupportingnodes(basegraph,edge1),getsupportingnodes(basegraph,edge2)))

##############################################################################
# Attributes
##############################################################################
#add or remove attributes from graphs and nodes
function setattribute(graph::AbstractPlasmoGraph,attribute::Symbol,value)
    basegraph = getbasegraph(graph)
    basegraph.attributes[attribute] = value
end
function setattribute(node::AbstractPlasmoNode,attribute::Symbol,value)
    basenode = getbasenode(node)
    basenode.attributes[attribute] = value
end
function setattribute(graph::AbstractPlasmoGraph,i::Int,attribute::Symbol,value)
    node = getnode(graph,i)
    basenode = getbasenode(node)
    addattribute!(basenode,attribute,value)
end

function addattributes!(node::AbstractPlasmoNode,dict::Dict)
    basenode = getbasenode(node)
    merge!(basenode.attributes,dict)
end

getattribute(graph::AbstractPlasmoGraph,attribute::Symbol) = getbasegraph(graph).attributes[attribute]
hasattribute(graph::AbstractPlasmoGraph,attribute::Symbol) = haskey(getbasegraph(graph).attributes,attribute)
getattribute(node::AbstractPlasmoNode,attribute::Symbol) = getbasenode(node).attributes[attribute]
hasattribute(node::AbstractPlasmoNode,attribute::Symbol) = haskey(getbasenode(node).attributes,attribute)

getattributes(graph::AbstractPlasmoGraph) = getbasegraph(graph).attributes
getattributes(node::AbstractPlasmoNode) = getbasenode(node).attributes

rmattribute!(node::AbstractPlasmoNode,attribute::Symbol) = delete!(getbasenode(node).attributes,attribute)
rmattribute!(graph::AbstractPlasmoGraph,attribute::Symbol) = delete!(getbasegraph(graph).attributes,attribute)


####################################
# Aliases
####################################
const add_node = add_node!
const add_edge = add_edge!
const add_subgraph = add_subgraph!

####################################
#Print Functions
####################################
function string(graph::AbstractPlasmoGraph)
    "graph_id: "*string(getlabel(graph))*"\nlightgraph:"*string(getlightgraph(graph))
end
print(io::IO, graph::AbstractPlasmoGraph) = print(io, string(graph))
show(io::IO,graph::AbstractPlasmoGraph) = print(io,graph)

function string(node::AbstractPlasmoNode)
    #"node: "string(getlabel(node))*string(" in $(length(getindices(node))) graph(s) with indices $(collect(values(getindices(node))))")
    "node "*getindices(node)
end
print(io::IO,node::AbstractPlasmoNode) = print(io, string(node))
show(io::IO,node::AbstractPlasmoNode) = print(io,node)

function string(edge::AbstractPlasmoEdge)
    #"edge: "*string(getlabel(edge))*string(" in $(length(getindices(edge))) graph(s) with ids $(collect(values(getindices(edge))))")
    "edge: "*string(getindices(edge))
end

#
# Copy function to get graph structure
#
function copy_graph(old_graph::AbstractPlasmoGraph; to_graph_type = typeof(old_graph))
    new_graph = to_graph_type()
    merge!(getbasegraph(old_graph).attributes,getbasegraph(new_graph).attributes)
    #new_base_graph = BasePlasmoGraph(typeof(basegraph.lightgraph)())
    #new_graph = to_graph_type(typeof(basegraph.lightgraph))
    #Add subgraphs
    for i = 1:length(getsubgraphlist(old_graph))
        subgraph = to_graph_type()
        add_subgraph!(new_graph,subgraph)
        #subgraph = to_graph_type(typeof(basegraph.lightgraph)())
        #subgraph = BasePlasmoGraph(typeof(basegraph.lightgraph)())
    end

    #Add nodes
    for node in getnodes(old_graph)
        #set index in top level graph
        node_index = getindex(old_graph,node)
        new_node = create_node(new_graph)
        add_node!(new_graph,new_node,index = node_index)  #add node to new graph

        merge!(getbasenode(node).attributes,getbasenode(new_node).attributes)

        #Get the other subgraphs this node is in
        subgraphs = collect(keys(getindices(node)))  #all graphs this node is in
        for subgraph in subgraphs
            subgraph_index = getindex(subgraph)
            if subgraph_index != 0  #already added to this one
                #Add to the subgraph
                new_subgraph = getsubgraph(new_graph,subgraph_index)
                node_index = getindex(subgraph,node)
                add_node!(new_subgraph,new_node,index = node_index)
            end
        end
    end

    #Add edges to each graph
    for edge in getedges(old_graph)
        edge_index = getindex(old_graph,edge)
        #add_edge!(new_base_graph,edge_index)
        add_edge!(new_graph,edge_index)

        for subgraph in getsubgraphlist(old_graph)
                subgraph_index = getindex(subgraph)
                for edge in getedges(subgraph)
                    edge_index = getindex(subgraph,edge)
                    new_subgraph = getsubgraph(new_graph,subgraph_index)
                    add_edge!(new_subgraph,edge_index)
                end
        end
    end
    return new_graph
end

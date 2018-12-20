#println("Testing Base Graph HyperGraph Functions")

using Plasmo.PlasmoGraphBase
using LightGraphs

basegraph1 = BasePlasmoGraph(HyperGraph)

# #Test adding nodes and edges in different ways
node1 = add_node!(basegraph1)
node2 = add_node!(basegraph1)
node3 = add_node!(basegraph1)
node4 = add_node!(basegraph1)
#
edge = HyperEdge(1,2)
e1 = add_edge!(basegraph1,edge)   #edge from 1 to 2

e2 = add_edge!(basegraph1,node2,node3)   #edge from 2 to 3
e3 = add_edge!(basegraph1,3,1)
e4 = add_edge!(basegraph1,node2,node3,node4)  #add a hyper edge

# OR
# nodes = [node2,node3,node4]
# e4 = add_edge!(basegraph1,nodes...)


# #
#Create a graph from a lightgraph
#NOTE This hangs
# g_lightgraph = DiGraph()
# add_vertex!(g_lightgraph)
# add_vertex!(g_lightgraph)
# add_edge!(g_lightgraph,1,2)
# # #
# basegraph2 = BasePlasmoGraph(g_lightgraph)
# add_node!(basegraph2)
#
# #Test getters and setters
getnodes(basegraph1)
getedges(basegraph1)
collectnodes(basegraph1)
collectedges(basegraph1)
getindex(basegraph1,node1)
getindex(basegraph1,e1)
# #
subgraph = BasePlasmoGraph(HyperGraph)
node_sub1 = add_node!(subgraph)
node_sub2 = add_node!(subgraph)
e_sub = add_edge!(subgraph,node_sub1,node_sub2)
#
add_subgraph!(basegraph1,subgraph)
# #
# #Test topology functions
# @assert src(basegraph1,e2) == node2
# @assert dst(basegraph1,e2) == node3
# #
# #Be careful, these only work for Directed graphs!
# in_edges(basegraph1,node2)
# out_edges(basegraph1,node2)
# in_neighbors(basegraph1,node2)
# out_neighbors(basegraph1,node2)
# #
degree(basegraph1,node2)
# in_degree(basegraph1,node2)
# out_degree(basegraph1,node2)
#
getsupportingedges(basegraph1,node2)
getsupportingnodes(basegraph1,e2)
#
return true

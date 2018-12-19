#println("Testing Base Graph Functions")

using Plasmo.PlasmoGraphBase
using LightGraphs

basegraph1 = BasePlasmoGraph(Graph)

# #Test adding nodes and edges in different ways
node1 = add_node!(basegraph1)
node2 = add_node!(basegraph1)
node3 = add_node!(basegraph1)
#
edge = LightGraphs.Edge(1,2)
e1 = add_edge!(basegraph1,edge)   #edge from 1 to 2
e2 = add_edge!(basegraph1,node2,node3)   #edge from 2 to 3
e3 = add_edge!(basegraph1,3,1)
# #
#Create a graph from a lightgraph
g_lightgraph = DiGraph()
add_vertex!(g_lightgraph)
add_vertex!(g_lightgraph)
add_edge!(g_lightgraph,1,2)
# #
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
#
subgraph = BasePlasmoGraph(Graph)
node_sub1 = add_node!(subgraph)
node_sub2 = add_node!(subgraph)
e_sub = add_edge!(subgraph,node_sub1,node_sub2)
#
add_subgraph!(basegraph1,subgraph)
#
#Test topology functions
@assert src(basegraph1,e2) == node2
@assert dst(basegraph1,e2) == node3
#
#Be careful, these only work for Directed graphs!
# in_edges(basegraph1,node2)
# out_edges(basegraph1,node2)
# in_neighbors(basegraph1,node2)
# out_neighbors(basegraph1,node2)
neighbors(basegraph1,node2)
#
degree(basegraph1,node2)
in_degree(basegraph1,node2)
out_degree(basegraph1,node2)

#TODO Need to come up with an implementation that facilitates this kind of querying
# getsupportingedges(basegraph1,node2)
# getsupportingnodes(basegraph1,e2)

return true

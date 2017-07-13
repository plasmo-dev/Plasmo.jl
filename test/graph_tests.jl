#Test all of the functions in graph.jl
using Plasmo
using LightGraphs

#Test PlasmoGraph constructor
g = PlasmoGraph()

#Test adding nodes and edges in different ways
node1 = add_node(g)
node2 = add_node(g)
node3 = add_node(g)

edge = LightGraphs.Edge(1,2)
e1 = add_edge(g,edge)
e2 = add_edge(g,node2,node3)
e3 = add_edge(g,3,1)

#Create a graph from a lightgraph
g_lightgraph = DiGraph()
add_vertex!(g_lightgraph)
add_vertex!(g_lightgraph)
add_edge(g_lightgraph,1,2)

g2 = PlasmoGraph(g_lightgraph)
new_node = create_node()
add_node(g2,new_node)
add_node(g2)

#Test getters and setters
getnodes(g)
getedges(g)
getnodeindex(g,node1)
getedgeindex(g,e1)

#Test attributes
addattribute!(g,:test,1)
addattribute!(node1,:test,2)
addattribute!(e1,:test,3)

addattribute!(g,1,:test2,1)
addattribute!(g,edge,:test2,2)

rmattribute!(g,:test)
rmattribute!(node1,:test)
rmattribute!(e1,:test)

#Test subgraphs
add_subgraph(g,g2)
getindex(g,node1)
getindex(g,new_node) #new_node is part of g2

#Test topology functions
src(g,e2)
dst(g,e2)
@assert src(g,e2) == node2
@assert dst(g,e2) == node3

in_edges(g,node2)
out_edges(g,node2)
in_neighbors(g,node2)
out_neighbors(g,node2)

degree(g,node2)
in_degree(g,node2)
out_degree(g,node2)

getsupportingedges(g,node2)
getsupportingnodes(g,e2)

true

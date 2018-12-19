module PlasmoGraphBase

#Import LightGraph Objects
import LightGraphs:AbstractGraph,AbstractEdge,Graph,DiGraph,

#Import LightGraph functions
add_vertex!,add_edge!,edgetype,nv,ne,vertices,edges,inneighbors,outneighbors,src,dst,degree,neighbors,is_directed,degree,all_neighbors,
is_connected,has_edge


import LightGraphs.SimpleGraphs.SimpleEdge
import Base:show,print,string,getindex,copy
import LightGraphs

export AbstractPlasmoGraph, AbstractPlasmoNode, AbstractPlasmoEdge,

#HyperGraph Object
HyperGraph, HyperEdge,

#BasePlasmoGraph
BasePlasmoGraph, BasePlasmoNode, BasePlasmoEdge,


getlightgraph,getbasegraph,getbasenode,getbaseedge,

getindex, getsubgraphlist, getsubgraph, getindices,getlabel,

getnodes,getedges,add_node,add_edge,add_node!,add_edge!,getnode,getedge,collectnodes,collectedges,create_node,

add_subgraph,add_subgraph!,getsubgraph,copy_graph,

in_degree,out_degree,getsupportingnodes,getsupportingedges,getconnectedto,getconnectedfrom,is_connected,
in_neighbors,out_neighbors,neighbors,has_edge,in_edges,out_edges,

getattribute,hasattribute,setattribute,addattributes!,getattributes

abstract type AbstractPlasmoGraph end
abstract type AbstractPlasmoNode end
abstract type AbstractPlasmoEdge end

include("hypergraph.jl")

include("node_edge_sets.jl")

include("basegraph.jl")

include("graph_interface.jl")

end

module PlasmoGraphBase

import LightGraphs:AbstractGraph,AbstractEdge,Graph,DiGraph,
add_vertex!,add_edge!,edgetype,nv,ne,vertices,edges,in_neighbors,out_neighbors,in_edges,out_edges,src,dst,degree,neighbors,is_directed,degree,all_neighbors,
is_connected

import LightGraphs.SimpleGraphs.SimpleEdge

import Base:show,print,string,getindex,copy

import LightGraphs

export AbstractPlasmoGraph, AbstractPlasmoNode, AbstractPlasmoEdge,

HyperGraph, HyperEdge,

BasePlasmoGraph, BasePlasmoNode, BasePlasmoEdge,

getlightgraph,getbasegraph,

getindex, getsubgraphlist, getsubgraph, getindices,getlabel,

getnodes,getedges,add_node,add_edge,add_node!,add_edge!,getnode,getedge,collectnodes,collectedges,

add_subgraph,add_subgraph!,getsubgraph,copy_graph,

in_degree,out_degree,getsupportingnodes,getsupportingedges,getconnectedto,getconnectedfrom,is_connected,neighbors,in_neighbors,out_neighbors,

hasattribute, getattribute,setattribute,addattributes!,getattributes

abstract type AbstractPlasmoGraph end
abstract type AbstractPlasmoNode end
abstract type AbstractPlasmoEdge end

include("hypergraph.jl")

include("node_edge_sets.jl")

include("basegraph.jl")

include("graph_interface.jl")

end

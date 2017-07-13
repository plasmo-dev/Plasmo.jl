#  Copyright 2017, Jordan Jalving, Yankai Cao, Victor Zavala, and contributors
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at http://mozilla.org/MPL/2.0/.
#############################################################################

#_precompile_(true)

module Plasmo

using Compat, MathProgBase, JuMP

export PlasmoGraph, PlasmoNode, PlasmoEdge, Node, Edge, NodeOrEdge,

#Plasmo graph functions
getnode,getedge,getnodeoredge,getconnectedto,getconnectedfrom,getsupportingnodes,getsupportingedges,is_connected,

#Add dispatch to LightGraphs.jl package functions
add_vertex!,add_edge!,add_node!,add_subgraph!,create_node,

nv,vertices,edges,src,dst,ne,

getvertexindex,getedgeindex,getnodeindex,getnodes,getedges,out_edges,out_degree,

out_neighbors,in_edges,in_degree,in_neighbors,degree,

#Attributes
addattribute!,rmattribute!,getattribute,hasattribute,_copy_subgraphs!,

#JuMP Models
GraphModel,FlatGraphModel,create_flat_graph_model,getmodel,hasmodel,
getgraph,getnodes,getedges,getnodesandedges,getnodevariables,getnodeobjective,getnodeconstraints,getlinkconstraints,getnodedata,getnode,
is_graphmodel,
setmodel!,solve,setsolution!,setvalue,

create_flat_graph_model,

#macros
@linkconstraint,@getconstraintlist

@compat abstract type AbstractPlasmoGraph end
@compat abstract type AbstractNode end
@compat abstract type AbstractEdge end

#typealias NodeOrEdge Union{AbstractNode,AbstractEdge}
const NodeOrEdge = Union{AbstractNode,AbstractEdge}

include("linkdata.jl")
include("graph.jl")
include("model.jl")
include("JuMPinterface.jl")
include("macros.jl")

#Pkg.installed("MPI")
#if isdefined(:MPI) #this doesn't work
# if  !isempty(Libdl.find_library("libparpipsnlp"))
#     include("solvers/plasmoPipsNlpInterface.jl") #TODO Check libraries
# end
# if !isempty(Libdl.find_library("libDsp"))
#     include("solvers/plasmoDspInterface.jl")     #TODO Check libraries
# end
#end


end

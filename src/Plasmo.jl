#  Copyright 2017, Jordan Jalving, Yankai Cao, Victor Zavala, and contributors
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at http://mozilla.org/MPL/2.0/.
#############################################################################

#_precompile_(true)

module Plasmo

using Compat, MathProgBase, JuMP

export PlasmoGraph, PlasmoNode, PlasmoEdge, Node, Edge, NodeOrEdge,GraphModel,

#Add dispatch to LightGraphs.jl package functions
add_vertex!,add_edge!,add_node!,nv,vertices,edges,src,dst,ne,degree,
in_edges,in_degree,in_neighbors,
out_edges,out_degree,out_neighbors,

#Plasmo graph functions
add_subgraph!,add_subgraph,setsolver,

#Node functions
create_node,add_node,getsupportingedges,getnodeindex,

#Edge functions
add_edge,getconnectedto,getconnectedfrom,getsupportingnodes,getedgeindex,

#Helper functions
getnode,getedge,getnodeoredge,getnodesandedges,is_connected,getnodes,getedges,contains_node,getsubgraphlist,

#Attributes
addattribute!,rmattribute!,getattribute,hasattribute,

#Model functions
setmodel,resetmodel,is_nodevar,getmodel,hasmodel,getlinkconstraints,getgraphobjectivevalue,getobjectivevalue,
buildserialmodel,getinternalgraphmodel,getsolution,

#The JuMP Extension
FlatGraphModel,create_flat_graph_model,
getgraph,getnodevariables,getnodeobjective,getnodeconstraints,getnodedata,is_graphmodel,
solve,setsolution,setvalue,

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
include("solution.jl")
include("macros.jl")

#load PIPS-NLP if the library can be found
if  !isempty(Libdl.find_library("libparpipsnlp"))
    include("solvers/plasmoPipsNlpInterface.jl")
    using .PlasmoPipsNlpInterface
    export pipsnlp_solve
end

#load DSP if the library can be found
if !isempty(Libdl.find_library("libDsp"))
    include("solvers/plasmoDspInterface.jl")
    using .PlasmoDspInterface
    export dsp_solve
end


end

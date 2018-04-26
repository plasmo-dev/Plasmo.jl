#  Copyright 2018, Jordan Jalving, Yankai Cao, Victor Zavala, and contributors
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at http://mozilla.org/MPL/2.0/.
#############################################################################
#_precompile_(true)

module Plasmo

export
##################
# BasePlasmoGraph
##################
AbstractPlasmoGraph, AbstractPlasmoNode, AbstractPlasmoEdge,

HyperGraph, HyperEdge,

BasePlasmoGraph, BasePlasmoNode, BasePlasmoEdge,

getlightgraph,getbasegraph,

getindex, getsubgraphlist, getsubgraph, getindices,getlabel,

getnodes,getedges,add_node,add_edge,add_node!,add_edge!,getnode,getedge,collectnodes,collectedges,

add_subgraph,add_subgraph!,getsubgraph,copy_graph,

in_degree,out_degree,getsupportingnodes,getsupportingedges,getconnectedto,getconnectedfrom,is_connected,

getattribute,setattribute,addattributes!,getattributes,


##################
#Model Graphs
##################

#Deprecations
PlasmoGraph,getgraphobjectivevalue,GraphModel,NodeOrEdge,create_flat_graph_model,

#ModelGraph
ModelGraph, ModelNode, LinkingEdge, LinkConstraint,

#Model functions
setmodel,setsolver,setmodel!,resetmodel,

is_nodevar,

getmodel,hasmodel,

addlinkconstraint, getlinkreferences,getlinkconstraints, getsimplelinkconstraints, gethyperlinkconstraints,get_all_linkconstraints,
getnumnodes,

getobjectivevalue,

getinternalgraphmodel,

#JuMP Interface functions
JuMPGraph,buildjumpmodel!,
#Internal JuMP models (when using JuMP solvers to solve the graph)
JuMPGraphModel,create_jump_graph_model,
#Try to make these work with Base JuMP commands
getgraph,getnodevariables,getnodevariable,getnodevariablemap,getnodeobjective,getnodeconstraints,getnodedata,is_graphmodel,

#solve handles
solve_jump,pipsnlp_solve,dsp_solve,solve,

#Solution management
getsolution,

setsolution,setvalue,

#macros
@linkconstraint,@getconstraintlist,

##################
#Workflows
##################
Workflow, DispatchNode, CommunicationEdge,SerialExecutor,

WorkflowEvent,NodeTriggerEvent,NodeCompleteEvent,EdgeTriggerEvent,CommunicationReceivedEvent,

add_dispatch_node!,initialize,

#Workflow
getcurrenttime,getnexttime,getnexteventtime,execute!,getevents,

#Dispatch Nodes
set_node_function,set_node_compute_time,set_node_function_arguments,set_node_function_kwargs,
getresult,setinputs,getlocaltime,

#Communication Edges
connect!,setdelay,getdelay,

#Node Channels
getinput,getoutput,getchanneldata_in,getchanneldata_out,getportdata,getnumchannels,getnodeinputdata,getnodeoutputdata,
set_result_slot_to_output_channel!,

#Events
gettriggers,addtrigger!,settrigger,trigger!,step,execute

include("PlasmoGraphBase/PlasmoGraphBase.jl")
using .PlasmoGraphBase

include("PlasmoModels/PlasmoModels.jl")
using .PlasmoModels

# include("PlasmoWorkflows/PlasmoWorkflows.jl")
# using .PlasmoWorkflows

end

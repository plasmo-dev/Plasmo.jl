#  Copyright 2018, Jordan Jalving, Yankai Cao, Victor Zavala, and contributors
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at http://mozilla.org/MPL/2.0/.
#############################################################################
#_precompile_(true)

module Plasmo

using Reexport
#export
##################
# BasePlasmoGraph
##################
# AbstractPlasmoGraph, AbstractPlasmoNode, AbstractPlasmoEdge,
#
# HyperGraph, HyperEdge,
#
# BasePlasmoGraph, BasePlasmoNode, BasePlasmoEdge,
#
# getlightgraph,getbasegraph,
#
# getindex, getsubgraphlist, getsubgraph, getindices,getlabel,
#
# getnodes,getedges,add_node,add_edge,add_node!,add_edge!,getnode,getedge,collectnodes,collectedges,
#
# add_subgraph,add_subgraph!,getsubgraph,copy_graph,
#
# in_degree,out_degree,getsupportingnodes,getsupportingedges,getconnectedto,getconnectedfrom,is_connected,
#
# getattribute,setattribute,addattributes!,getattributes,
#
#
# ##################
# #Model Graphs
# ##################
#
# #Deprecations
# PlasmoGraph,getgraphobjectivevalue,GraphModel,NodeOrEdge,create_flat_graph_model,
#
# #ModelGraph
# ModelGraph, ModelNode, LinkingEdge, LinkConstraint,
#
# #Model functions
# setmodel,setsolver,setmodel!,resetmodel,
#
# is_nodevar,
#
# getmodel,hasmodel,
#
# addlinkconstraint, getlinkreferences,getlinkconstraints, getsimplelinkconstraints, gethyperlinkconstraints,get_all_linkconstraints,
# getnumnodes,
#
# getobjectivevalue,
#
# getinternalgraphmodel,
#
# #Graph Manipulation Functions
# aggregate!,
#
# #JuMP Interface functions
# JuMPGraph,buildjumpmodel!,
# #Internal JuMP models (when using JuMP solvers to solve the graph)
# JuMPGraphModel,create_jump_graph_model,
# #Try to make these work with Base JuMP commands
# getgraph,getnodevariables,getnodevariable,getnodevariablemap,getnodeobjective,getnodeconstraints,getnodedata,is_graphmodel,
#
# #solve handles
# solve_jump,pipsnlp_solve,dsp_solve,solve,
#
# #Solution management
# getsolution,
#
# setsolution,setvalue,
#
# #macros
# @linkconstraint,@getconstraintlist,
#
# ##################
# #Workflows
# ##################
# AbstractSignal,AbstractEvent,SerialExecutor,
#
# StateManager,SignalCoordinator,SignalEvent,
#
# State,Signal,DataSignal,Transition,TransitionAction,
#
# addstate!,addsignal!,addtransition!,addbroadcasttarget!,
#
# setstate,schedulesignal,step,advance,
#
# getsignals,getstates,getinitialsignal,getcurrentstate,gettransitionfunction,gettransitions,gettransition,
#
#
# #WORKFLOWS
#
# Workflow, DispatchNode, CommunicationEdge,
#
# #Workflow functions
#
# initialize,
#
# add_dispatch_node!,add_continuous_node!,
#
# set_node_task,set_node_task_arguments,set_node_compute_time,
#
# #Attributes
# addattribute!,getattribute,getattributes,
# getlocalvalue,getglobalvalue,getvalue,
#
# #Workflow
# getcurrenttime,getnexttime,getnexteventtime,initialize,execute!,getqueue,
#
# #Dispatch Nodes
# set_node_function,set_node_compute_time,set_node_function_arguments,set_node_function_kwargs,
# getresult,setinputs,getlocaltime,setinitialsignal,
#
# #Communication Edges
# connect!,setdelay,getdelay

#Include and Use Modules
include("PlasmoGraphBase/PlasmoGraphBase.jl")
@reexport using .PlasmoGraphBase

include("ModelGraph/PlasmoModelGraph.jl")
@reexport using .PlasmoModelGraph

include("ComputingGraph/PlasmoComputingGraph.jl")
@reexport using .PlasmoComputingGraph
end

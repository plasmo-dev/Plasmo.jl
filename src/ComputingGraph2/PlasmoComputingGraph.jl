module PlasmoComputingGraph

using ..PlasmoGraphBase
import ..PlasmoGraphBase:create_node,create_edge,add_edge!,addattributes!

import DataStructures
import Base:isless,step,==,show,print,string,getindex


export AbstractSignal,SerialExecutor,

#State Manager objects
StateManager,SignalQueue, State,Signal,Transition,TransitionAction,

addstate!,addsignal!,addtransition!,setstate,setaction,

getsignals,getstates,getcurrentstate,gettransitions,gettransition,getaction,

step,advance,queuesignal!


#Computing Graph
#
# Workflow, DispatchNode, CommunicationEdge,Attribute, StopWorkflow,
#
# add_dispatch_node!,add_continuous_node!,
#
# set_node_task,set_node_task_arguments,set_node_compute_time,
#
# addnodetask!,getnodetask,getnodetasks,setcomputetime,
#
# #Attributes
# addworkflowattribute!,
#
# getworkflowattribute,setworkflowattribute,
#
# getworkflowattributes,
#
# getlocalvalue,getglobalvalue,getvalue,getnoderesult,
#
# updateattribute,
#
# #Workflow
# getcurrenttime,getnexttime,getnexteventtime,initialize,execute!,getqueue,
#
# #Dispatch Nodes
# set_node_function,set_node_compute_time,set_node_function_arguments,set_node_function_kwargs,
# getresult,setinputs,getlocaltime,setinitialsignal,getlabel,addtrigger!,
#
# #Communication Edges
# connect!,setdelay,getdelay

abstract type AbstractComputingGraph <: AbstractPlasmoGraph end
abstract type AbstractComputeNode <: AbstractPlasmoNode end
abstract type AbstractCommunicationEdge  <: AbstractPlasmoEdge end

abstract type AbstractAttribute end
abstract type AbstractSignalEvent end
abstract type AbstractSignal end
abstract type AbstractStateManager end
abstract type AbstractSignalQueue end

const SignalTarget = Union{AbstractStateManager,AbstractComputeNode,AbstractCommunicationEdge}   #A node can be a target

#State Manager
include("state_manager/states_signals.jl")
include("state_manager/signal_event.jl")
include("state_manager/state_manager.jl")
include("state_manager/signal_queue.jl")
include("state_manager/signal_executor.jl")
include("state_manager/print.jl")

#Computation Graph

#Node Tasks
# include("node_task.jl")
#
# #Workflow Attributes
# include("attribute.jl")
#
# include("implemented_states_signals.jl")
#
# #Node and Edge Transition Actions
# include("actions.jl")
#
# #The workflow Graph
# include("workflow_graph.jl")
# #
# #Edges for communication between nodes
# include("communication_edges.jl")
# #
# #Discrete and continuous dispatch nodes
# include("dispatch_nodes.jl")
# #
# # #Workflow execution
# include("workflow_executor.jl")

end # module

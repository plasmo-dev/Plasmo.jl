module PlasmoComputingGraph

using ..PlasmoGraphBase
import ..PlasmoGraphBase:create_node,create_edge,add_edge!,addattributes!

import DataStructures
import Base:isless,step,==,show,print,string,getindex


export AbstractSignal,SerialExecutor,

#State Manager objects
StateManager,SignalQueue,State,Signal,Transition,TransitionAction,

addstate!,addsignal!,addtransition!,setstate,setaction,

getsignals,getstates,getcurrentstate,gettransitions,gettransition,getaction,

step,advance,execute!queuesignal!,


#Computing Graph Objects
ComputingGraph, ComputeNode, CommunicationEdge,NodeAttribute,

#Computing Graph functions
getqueue,stop_graph,

#NodeTask
addnodetask!,getnodetask,getnodetasks,setcomputetime,

#Compute Attributes
addcomputeattribute!,getcomputeattribute,getcomputeattributes,getlocalvalue,getglobalvalue,getvalue,setvalue,

#Compute Nodes
addnode!,addtrigger!,

#Communication Edges
addedge!,setdelay,getdelay,iscommunicating,

#  Time access
now,getcurrenttime,getnexttime,getnexteventtime,getlocaltime

abstract type AbstractComputingGraph <: AbstractPlasmoGraph end
abstract type AbstractComputeNode <: AbstractPlasmoNode end
abstract type AbstractCommunicationEdge  <: AbstractPlasmoEdge end

abstract type AbstractAttribute end
abstract type AbstractSignalEvent end
abstract type AbstractSignal end
abstract type AbstractStateManager end
abstract type AbstractSignalQueue end

const SignalTarget = Union{AbstractStateManager,AbstractComputeNode,AbstractCommunicationEdge}   #A node can be a target

#State Manager Backend
include("state_manager/states_signals.jl")
include("state_manager/signal_event.jl")
include("state_manager/state_manager.jl")
include("state_manager/signal_queue.jl")
include("state_manager/signal_executor.jl")
include("state_manager/print.jl")

#Computing Graph Interface

include("implemented_states_signals.jl")

#Node Tasks
include("node_task.jl")

#Compute Attributes
include("attributes.jl")

#Transition Actions
include("actions.jl")

#The Computing Graph
include("computing_graph.jl")

#Communication Edges
include("communication_edges.jl")

#Compute Nodes
include("compute_nodes.jl")

#Execution
include("workflow_executor.jl")

end # module

#set_node_task,set_node_task_arguments,

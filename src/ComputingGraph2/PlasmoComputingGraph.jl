module PlasmoComputingGraph

using ..PlasmoGraphBase
import ..PlasmoGraphBase:create_node,create_edge,add_edge!,addattributes!#,getattribute,getattributes,

import LightGraphs.DiGraph
import DataStructures
import Base:isless,step,==,show,print,string,getindex


#State manager functions
export AbstractSignal,AbstractEvent,SerialExecutor,

StateManager,SignalCoordinator,SignalEvent,

State,Signal,Transition,TransitionAction,

addstate!,addsignal!,addtransition!,addbroadcasttarget!,

setstate,schedulesignal,step,advance,

getsignals,getstates,getinitialsignal,getcurrentstate,gettransitionfunction,gettransitions,gettransition,


#WORKFLOWS

Workflow, DispatchNode, CommunicationEdge,Attribute, StopWorkflow,

#Workflow functions

initialize,

add_dispatch_node!,add_continuous_node!,

set_node_task,set_node_task_arguments,set_node_compute_time,

addnodetask!,getnodetask,getnodetasks,setcomputetime,

#Attributes
addworkflowattribute!,

getworkflowattribute,setworkflowattribute,

getworkflowattributes,

getlocalvalue,getglobalvalue,getvalue,getnoderesult,

updateattribute,

#Workflow
getcurrenttime,getnexttime,getnexteventtime,initialize,execute!,getqueue,

#Dispatch Nodes
set_node_function,set_node_compute_time,set_node_function_arguments,set_node_function_kwargs,
getresult,setinputs,getlocaltime,setinitialsignal,getlabel,addtrigger!,

#Communication Edges
connect!,setdelay,getdelay


abstract type AbstractComputingGraph <: AbstractPlasmoGraph end
abstract type AbstractComputeNode <: AbstractPlasmoNode end
abstract type AbstractCommunicationEdge  <: AbstractPlasmoEdge end

abstract type AbstractAttribute end
abstract type AbstractEvent end
abstract type AbstractSignal end
abstract type AbstractStateManager end
abstract type AbstractSignalQueue end

const SignalTarget = Union{AbstractStateManager,AbstractComputeNode,AbstractCommunicationEdge}   #A node can be a target

#State Manager and Coordination
include("state_manager/signal_event.jl")
include("state_manager/state_manager.jl")
include("state_manager/signal_coordinator.jl")
include("state_manager/signal_executor.jl")
include("state_manager/signal_print.jl")

#Computation Graph

#Node Tasks
include("node_task.jl")

#Workflow Attributes
include("attribute.jl")

include("implemented_states_signals.jl")

#Node and Edge Transition Actions
include("actions.jl")

#The workflow Graph
include("workflow_graph.jl")
#
#Edges for communication between nodes
include("communication_edges.jl")
#
#Discrete and continuous dispatch nodes
include("dispatch_nodes.jl")
#
# #Workflow execution
include("workflow_executor.jl")

end # module

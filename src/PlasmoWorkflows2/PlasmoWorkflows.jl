module PlasmoWorkflows

using ..PlasmoGraphBase

import PlasmoGraphBase:create_node,create_edge,add_edge!
import LightGraphs.DiGraph
import DataStructures
import Base:isless,step

export Workflow, DispatchNode, CommunicationEdge,SerialExecutor,

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

abstract type AbstractWorkflow <: AbstractPlasmoGraph end
abstract type AbstractDispatchNode <: AbstractPlasmoNode end
abstract type AbstractCommunicationEdge  <: AbstractPlasmoEdge end

abstract type AbstractEvent end
abstract type AbstractSignal end
abstract type AbstractStateManager end
abstract type AbstractSignalCoordinator end


#abstract type AbstractSignalTarget <: Union{AbstractDispatchNode,AbstractCommunicationEdge} end

# #Events can be: Event, Condition, Delay, Communicate, etc...
# abstract type AbstractWorkflowEvent <: AbstractEvent end   #General Events
# abstract type AbstractNodeEvent <: AbstractEvent end       #Events triggered by nodes
# abstract type AbstractEdgeEvent <: AbstractEvent end

#the workflow graph
include("dispatch_function.jl")

#the workflow graph
include("workflow_graph.jl")

#input and output channels for nodes
#include("data_channels.jl")

#Workflow events, node triggers, and edge triggers
include("signal_event.jl")

#edges for communication between nodes
include("communication_edges.jl")

#discrete and continuous dispatch nodes
include("dispatch_nodes.jl")

#the event priority queue and the executors which manage it
include("executor.jl")

end # module

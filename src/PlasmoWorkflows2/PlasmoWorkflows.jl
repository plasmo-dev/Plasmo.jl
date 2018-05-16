module PlasmoWorkflows

include("../PlasmoGraphBase/PlasmoGraphBase.jl")

using .PlasmoGraphBase

import PlasmoGraphBase:create_node,create_edge,add_edge!
import LightGraphs.DiGraph
import DataStructures
import Base:isless,step

export StateManager,SignalCoordinator,SignalEvent,

Workflow, DispatchNode, CommunicationEdge, SerialExecutor,

add_dispatch_node!,add_continuous_node!,initialize,

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

const SignalTarget = AbstractStateManager
# #Events can be: Event, Condition, Delay, Communicate, etc...
# abstract type AbstractWorkflowEvent <: AbstractEvent end   #General Events
# abstract type AbstractNodeEvent <: AbstractEvent end       #Events triggered by nodes
# abstract type AbstractEdgeEvent <: AbstractEvent end

#State Manager and Coordination
include("state_manager/signal_event.jl")
include("state_manager/state_manager.jl")
include("state_manager/signal_coordinator.jl")

#Workflow Graph

# #Node Tasks
# include("dispatch_function.jl")
#
# #Node and Edge Transition Actions
# include("actions.jl")
#
# #The workflow Graph
# include("workflow_graph.jl")
#
# #Workflow Attributes
# include("attribute.jl")
#
# #Edges for communication between nodes
# include("communication_edges.jl")
#
# #Discrete and continuous dispatch nodes
# include("dispatch_nodes.jl")
#
# #Workflow execution
# include("executor.jl")

# function gettransitionactions()
#     return schedule_node,run_node_task
# end

end # module

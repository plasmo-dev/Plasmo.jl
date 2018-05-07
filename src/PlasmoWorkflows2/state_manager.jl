abstract type AbstractSignal end

#Signal can be an input or output
struct Signal <: AbstractSignal
    label::Symbol
    targets#::StateManager
    value::Any  #Attribute, or other value
end
Signal() = Signal(:empty,nothing)

const State = Symbol
const Transition = Tuple{State,Signal,State}
const SignalTarget = Union{AbstractDispatchNode,AbstractCommunicationEdge}

struct StateManager
    states::Vector{State}            #possible states
    current_state::State             #current state
    signals::Vector{AbstractSignal}  #signal the manager recognizes
    transition_map::Dict{Tuple{State,Signal},State}             #Allowable transitions for this state manager
    transition_functions::Dict{Transition,DispatchFunction}     #Returns a signal.  This will run the associated function
    signal_broadcast_map::Dict{Transition,Vector{Union{DispatchNode,CommunicationEdge}}}   #Transition (Output) Map of output signals to targets
end
#Constructor
function StateManager()
    states = State[]
    current_state = nothing
    signals = Signal[]
    transition_map = Dict{Tuple{State,Signal},State}()
    transition_functions::Dict{Transition,DispatchFunction}
    signal_broadcast_map = Dict{Transition,Vector{Union{DispatchNode,CommunicationEdge}}}()
    return StateManager(states,current_state,signals,transition_map,transition_functions,signal_broadcast_map)
end

function setstate(SM::StateManager,state::State)
    @assert state in SM.states
    SM.current_state = state
end

function setstates(SM::StateManager,states::Vector{State})
    @assert SM.current_state in states
    SM.states = states
end




getsignals(SM::StateManager) = SM.signals
getstates(SM::StateManager) = SM.states
getcurrentstate(SM::StateManager) = SM.current_state
gettransitionfunc(SM::StateManager,transition::Transition) = SM.transition_functions[transition]

#Receive a signal and run the corresponding transition function.  Return a new signal.
function evaluate_signal(SM::StateManager,signal::Signal)
    current_state = getstate(SM)
    if !(signal in getsignals(SM))
        return nothing
    end
    if !(tuple(current_state,signal) in keys(SM.transition_map))
        return nothing
    end
    new_state = SM.transition_map[tuple(current_state,signal)]
    transition = tuple(current_state,signal,new_state)
    setstate(SM,new_state)
    dfunc = gettransitionfunc(SM,transition)         #e.g. run_task or communicate

    run!(dfunc,SM.signal_broadcast_map[transition])
end


#@enum state idle = 1 scheduled = 2 computing = 3 synchronizing = 4 error = 5 inactive = 6 active = 7
#Previous State, signal, new state
# struct Transition
#     previous_state::State
#     input_signal::Signal
#     new_state::State
# end
# Transition() =  Transition(:empty,Signal(),:empty)

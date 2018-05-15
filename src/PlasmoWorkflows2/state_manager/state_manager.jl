struct State
    label::Symbol
end
State() = State(:null)
State(label::Symbol) = State(label)

#Signal for mapping behaviors
struct Signal <: AbstractSignal
    label::Symbol
    value::Any  #Attribute, or other value, or even an Array
end
Signal(sym::Symbol) = Signal(sym,nothing,nothing)
Signal() = Signal(:empty,nothing,nothing)

#A signal carrying information
mutable struct DataSignal <: AbstractSignal
    label::Symbol
    value::Any              #Attribute, or other value, or even an Array
    data::Any               #Data the signal may carry.  Can be passed to transition actions.
end

==(signal1::AbstractSignal,signal2::AbstractSignal) = (signal1.label == signal2.label && signal1.value == signal2.value)
getlabel(signal::AbstractSignal) = signal.label
getvalue(signal::AbstractSignal) = signal.value
getdata(signal::AbstractSignal) = nothing
getdata(signal::DataSignal) = signal.data
const SignalTarget = AbstractStateManager

#############################################
# Transition Action
#############################################
mutable struct TransitionAction
    func::Function                                  #the function to call
    args::Vector{Any}                               #the function args
    kwargs::Dict{Any,Any}                           #possible kwargs
    result::Vector{Pair{Signal,Float64}}            #action returns a signal and delay
end

TransitionAction() = TransitionAction(() -> [Pair(Signal(:nothing),0)],[],Dict(),Vector{Pair{Signal,Float64}}())
#NOTE May not use this run function
function run!(action::TransitionAction)
    action.result = action.func(action.args...,action.kwargs...)
    return action.result  #will be a vector of signals and times
end

#NOTE Makes more sense to pass the triggering signal to the transition action
function run!(action::TransitionAction,triggering_signal::AbstractSignal)  #Transition action and signal that triggered it
    action.result = action.func(triggering_signal,action.args...,action.kwargs...)
    return action.result  #will be a vector of signals and times
end

#############################################
# Transition
#############################################
mutable struct Transition
    starting_state::State
    input_signal::Signal
    new_state::State
    action::TransitionAction
    signal_targets::Vector{SignalTarget}
end
Transition() =  Transition(State(),Signal(),State(),TransitionAction(),SignalTarget[])

#############################################
# State Manager
#############################################
mutable struct StateManager <: AbstractStateManager
    states::Vector{State}            #possible states
    current_state::State             #current state
    signals::Vector{AbstractSignal}  #signal the manager recognizes
    transition_map::Dict{Tuple{State,Signal},Transition}             #Allowable transitions for this state manager
end

#Constructor
StateManager() = StateManager(State[],State(),Signal[],Dict{Tuple{State,Signal},State}(),Dict{Transition,Vector{SignalTarget}}())

getsignals(SM::StateManager) = SM.signals
getstates(SM::StateManager) = SM.states
gettransitions(SM::StateManager) = collect(values(SM.transition_map))
getcurrentstate(SM::StateManager) = SM.current_state
gettransitionfunction(transition::Transition) = transition.action  #return a dispatch function

function setstate(SM::StateManager,state::State)
    @assert state in SM.states
    SM.current_state = state
end

function setstates(SM::StateManager,states::Vector{State})
    @assert SM.current_state in states
    SM.states = states
end

function addtransition!(SM::StateManager,state1::State,signal::Signal,state2::State;action = TransitionAction(),targets = SignalTarget[])
    transition = Transition(state1,signal,state2,action,targets)
    SM.transtion_map[tuple(state1,signal)] = transition
end

function addbroadcasttarget!(transition::Transition,target::SignalTarget)
    push!(transition.signal_targets,target)
end

function runtransition!(SM::StateManager,transition::Transition,triggering_signal::AbstractSignal)
    current_state = getstate(SM)
    if current_state == transition.starting_state
        new_state = transition.new_state
        setstate(SM,new_state)
        return run!(transition.action,triggering_signal)  #returns signals
    else
        #NOTE Return something more helpful
        return nothing
    end
end

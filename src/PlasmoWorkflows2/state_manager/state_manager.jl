struct State
    label::Symbol
end
State() = State(:null)
#State(label::Symbol) = State(label)

#Signal for mapping behaviors
struct Signal <: AbstractSignal
    label::Symbol
    value::Any  #Attribute, or other value to compare on
end
Signal(sym::Symbol) = Signal(sym,nothing)
Signal() = Signal(:empty,nothing)

#A signal carrying information
mutable struct DataSignal <: AbstractSignal
    label::Symbol
    value::Any              #Attribute, or other value, or even an Array
    data::Any               #Data the signal may carry.  Can be passed to transition actions.
end

#NOTE Just use a convert method here?
Signal(signal::DataSignal) = Signal(signal.label,signal.value)  #Convert data signal to a signal

==(signal1::AbstractSignal,signal2::AbstractSignal) = (signal1.label == signal2.label && signal1.value == signal2.value)
getlabel(signal::AbstractSignal) = signal.label
getvalue(signal::AbstractSignal) = signal.value
getdata(signal::AbstractSignal) = nothing
getdata(signal::DataSignal) = signal.data


#############################################
# Transition Action
#############################################
mutable struct TransitionAction
    func::Function                                  #the function to call
    args::Vector{Any}                               #the function args
    kwargs::Dict{Any,Any}                           #possible kwargs
    result::Vector{Pair{AbstractSignal,Float64}}            #action returns a signal and delay
end
TransitionAction() = TransitionAction((signal::AbstractSignal) -> [Pair(Signal(:nothing),0)],[],Dict(),Vector{Pair{Signal,Float64}}())
TransitionAction(func::Function) = TransitionAction(func,[],Dict(),Vector{Pair{Signal,Float64}}())
TransitionAction(func::Function,args::Vector) = TransitionAction(func,args,Dict(),Vector{Pair{Signal,Float64}}())


# #NOTE May not use this run function
# function run!(action::TransitionAction)
#     action.result = action.func(action.args...,action.kwargs...)
#     return action.result  #will be a vector of signals and times
# end

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
    input_signal::AbstractSignal
    new_state::State
    action::TransitionAction
    output_signal_targets::Vector{SignalTarget}
end
Transition() =  Transition(State(),Signal(),State(),TransitionAction(),SignalTarget[])

#############################################
# State Manager
#############################################
mutable struct StateManager <: AbstractStateManager
    states::Vector{State}            #possible states
    current_state::State             #current state
    signals::Vector{AbstractSignal}  #signal the manager recognizes
    transition_map::Dict{Tuple{State,AbstractSignal},Transition}             #Allowable transitions for this state manager
    initial_signal::Union{Void,AbstractSignal}
end

#Constructor
StateManager() = StateManager(State[],State(),Signal[],Dict{Tuple{State,AbstractSignal},Transition}(),nothing)

getsignals(SM::StateManager) = SM.signals
getinitialsignal(SM::StateManager) = SM.initial_signal
getstates(SM::StateManager) = SM.states
gettransitions(SM::StateManager) = collect(values(SM.transition_map))
gettransition(SM::StateManager,state::State,signal::AbstractSignal) = SM.transition_map[tuple(state,signal)]
getcurrentstate(SM::StateManager) = SM.current_state
gettransitionfunction(transition::Transition) = transition.action  #return a dispatch function

addsignal!(SM::StateManager,signal::AbstractSignal) = signal in SM.signals? nothing : push!(SM.signals,signal)
addsignal!(SM::StateManager,signal::Symbol) = addsignal!(SM,Signal(signal))
addstate!(SM::StateManager,state::State) = state in SM.states? nothing : push!(SM.states,state)
addstate!(SM::StateManager,state::Symbol) = addstate!(SM,State(state))

function setstate(SM::StateManager,state::State)
    @assert state in SM.states
    SM.current_state = state
end

setstate(SM::StateManager,state::Symbol) = setstate(SM,State(state))

function setstates(SM::StateManager,states::Vector{State})
    @assert SM.current_state in states
    SM.states = states
end

function setstates(SM::StateManager,states::Vector{Symbol})
    states = [State(state) for state in states]
    @assert SM.current_state in states
    SM.states = states
end

function setinitialsignal(SM::StateManager,signal::AbstractSignal)
    SM.initial_signal = signal
end

function addtransition!(SM::StateManager,state1::State,signal::AbstractSignal,state2::State;action = TransitionAction(),targets = SignalTarget[])
    transition = Transition(state1,signal,state2,action,targets)
    addtransition!(SM,transition)
    #SM.transition_map[tuple(state1,signal)] = transition
    return transition
end

function addtransition!(SM::StateManager,transition::Transition)
    addsignal!(SM,transition.input_signal)
    addstate!(SM,transition.starting_state)
    addstate!(SM,transition.new_state)
    SM.transition_map[tuple(transition.starting_state,transition.input_signal)] = transition
    return transition
end


function addbroadcasttarget!(transition::Transition,target::SignalTarget)
    push!(transition.output_signal_targets,target)
end

function runtransition!(SM::StateManager,transition::Transition,triggering_signal::AbstractSignal)
    current_state = getcurrentstate(SM)
    if current_state == transition.starting_state
        new_state = transition.new_state
        setstate(SM,new_state)
        result = run!(transition.action,triggering_signal)
        return result  #returns signals
    else
        #NOTE Return something more helpful
        return nothing
    end
end

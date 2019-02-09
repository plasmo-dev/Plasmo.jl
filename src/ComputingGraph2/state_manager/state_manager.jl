#Define a transition
const Transition = Tuple{State,AbstractSignal,State}

abstract type AbstractTransitionAction end
#############################################
# Transition Action
#############################################
mutable struct TransitionAction <: AbstractTransitionAction
    func::Function                                  #the function to call
    args::Vector{Any}                               #the function args
    kwargs::Dict{Symbol,Any}                        #possible kwargs
end

#Constructor
TransitionAction(func::Function) = TransitionAction(func,[],Dict())
TransitionAction(func::Function,args::Vector) = TransitionAction(func,args,Dict())

#Run transition action
run_action!(action::TransitionAction) = action.func(action.args...,action.kwargs...)  #run a transition action
getarguments(action::AbstractTransitionAction) = action.args
getkwarguments(action::AbstractTransitionAction) = action.kwargs

#############################################
# State Manager
#############################################
mutable struct StateManager <: AbstractStateManager
    valid_states::Vector{State}                                                       #possible states
    current_state::State                                                              #current state
    valid_signals::Vector{AbstractSignal}                                             #state manager recognizes these signals
    transition_map::Dict{Tuple{State,AbstractSignal},State}                                   #x^+ = f(x,u)
    action_map::Dict{Tuple{State,AbstractSignal},Union{Nothing,AbstractTransitionAction}}     #eta^+ = g(eta)
    active_signals::Vector{SignalEvent}                                               #vector of signal events this state manager has to evaluate
end

#Constructor
function StateManager()
    valid_states = State[]
    current_state = State()
    valid_signals = Signal[]
    transition_map = Dict{Tuple{State,AbstractSignal},State}()
    action_map = Dict{Tuple{State,AbstractSignal},Union{Nothing,AbstractTransitionAction}}()
    active_signals = SignalEvent[]
    return StateManager(valid_states,current_state,valid_signals,transition_map,action_map,active_signals)
end

getstatemanager(SM::StateManager) = SM
getvalidsignals(SM::StateManager) = SM.valid_signals
getstates(SM::StateManager) = SM.valid_states
getstate(SM::StateManager) = SM.current_state
getcurrentstate(SM::StateManager) = SM.current_state

addsignal!(SM::StateManager,signal::AbstractSignal) = signal in SM.valid_signals ? nothing : push!(SM.valid_signals,signal)
addsignal!(SM::StateManager,signal::Symbol) = addsignal!(SM,Signal(signal))
addstate!(SM::StateManager,state::State) = state in SM.valid_states ? nothing : push!(SM.valid_states,state)
addstate!(SM::StateManager,state::Symbol) = addstate!(SM,State(state))

# Add valid states
function addstates!(SM::StateManager,states::Vector{State})
    append!(SM.valid_states,states)
end
function addstates!(SM::StateManager,states::Vector{Symbol})
    states = [State(state) for state in states]
    append!(SM.valid_states,states)
end

# Set current state
function setstate(SM::StateManager,state::State)
    @assert state in SM.valid_states
    SM.current_state = state
end
setstate(SM::StateManager,state::Symbol) = setstate(SM,State(state))

# Set valid states
function setvalidstates(SM::StateManager,states::Vector{State})
    @assert SM.current_state in states
    SM.valid_states = states
end
function setvalidstates(SM::StateManager,states::Vector{Symbol})
    states = [State(state) for state in states]
    @assert SM.current_state in states
    SM.valid_states = states
end

function addtransition!(target::SignalTarget,state1::State,signal::AbstractSignal,state2::State; action::Union{Nothing,AbstractTransitionAction} = nothing)
    SM = getstatemanager(target)
    SM.transition_map[tuple(state1,signal)] = state2
    if action != nothing
        SM.action_map[tuple(state1,signal)] = action
    end
    return tuple(state1,signal,state2)
end

function addtransition!(target::SignalTarget,transition::Transition)
    SM = getstatemanager(target)
    addstate!(SM,transition[1])
    addsignal!(SM,transition[2])
    addstate!(SM,transition[3])
    SM.transition_map[tuple(transition[1],transition[2])] = transition[3]
    return transition
end

function hastransition(target::SignalTarget,state1::State,signal::AbstractSignal)
    SM = getstatemanager(target)
    return haskey(SM.transition_map,tuple(state1,signal))
end

function setaction(target::SignalTarget,transition::Transition,action::AbstractTransitionAction)
    SM = getstatemanager(target)
    SM.action_map[tuple(transition[1],transition[2])] = action
end

function hasaction(target::SignalTarget,state1::State,signal::AbstractSignal)
    SM = getstatemanager(target)
    return haskey(SM.action_map,tuple(state1,signal))
end

function runtransition!(target::SignalTarget,input_signal::Signal)
    SM = getstatemanager(target)
    start_state = getstate(SM)
    if hastransition(SM,start_state,input_signal)
        new_state = SM.transition_map[start_state,input_signal]
        setstate(SM,new_state)
        if hasaction(SM,start_state,input_signal)
            action = SM.action_map[start_state,input_signal]
            run_action!(action)
        end
    else
        error("Target has no transition for state: $(start_state) with signal $(input_signal)")
    end
end

gettransitions(target::SignalTarget) = [[k[1],k[2],v] for (k,v) in getstatemanager(target).transition_map]

function gettransition(target::SignalTarget,state::State,signal::AbstractSignal)
    SM = getstatemanager(target)
    if hastransition(SM,state,signal)
        return [state,signal,SM.transition_map[tuple(state,signal)]]
    else
        return nothing
    end
end

# function addbroadcasttarget!(SM::StateManager,signal::AbstractSignal,output_target::SignalTarget)
#     if !(target in SM.broadcast_map[signal])
#         push!(SM.broadcast_map[signal],target)
#     end
# end
#getlocaltime(SM::StateManager) = SM.local_time
# function setinitialsignal(SM::StateManager,signal::AbstractSignal)
#     SM.initial_signal = signal
# end
#getinitialsignal(SM::StateManager) = SM.initial_signal

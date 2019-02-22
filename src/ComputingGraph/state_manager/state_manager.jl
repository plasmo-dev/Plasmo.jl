#Define a transition
const Transition = Tuple{State,AbstractSignal,Union{Nothing,State}}

abstract type AbstractTransitionAction end
#############################################
# Transition Action
#############################################
mutable struct TransitionAction <: AbstractTransitionAction
    func::Function                                  #the function to call
    args::Vector{Any}                               #the function args
    kwargs::Dict{Symbol,Any}                        #possible kwargs
    #transition::Transition
end

#Constructor
TransitionAction(func::Function) = TransitionAction(func,[],Dict())
TransitionAction(func::Function,args::Vector) = TransitionAction(func,args,Dict())

#Run transition action
function runaction!(input_signal::Signal,action::TransitionAction)
    action.func(input_signal,action.args...,action.kwargs...)  #run a transition action
end
getarguments(action::AbstractTransitionAction) = action.args
getkwarguments(action::AbstractTransitionAction) = action.kwargs
gettransition(action::AbstractTransitionAction) = action.transition

#############################################
# State Manager
#############################################
mutable struct StateManager <: AbstractStateManager
    valid_states::Vector{State}                                                       #possible states
    current_state::State                                                              #current state
    valid_signals::Vector{AbstractSignal}                                             #state manager recognizes these signals
    # transition_map::Dict{Tuple{State,AbstractSignal},State}                                             #x^+ = f(x,u)
    # action_map::Dict{Tuple{State,AbstractSignal},Vector{Union{Nothing,AbstractTransitionAction}}}       #eta^+ = g(eta)
    transition_map::Dict{TransitionPair,Union{Nothing,State}}
    action_map::Dict{TransitionPair,Vector{Union{Nothing,AbstractTransitionAction}}}
    active_signals::Vector{SignalEvent}                                               #vector of signal events this state manager has to evaluate
end

#Constructor
function StateManager()
    valid_states = State[]
    current_state = State()
    valid_signals = Signal[]
    # transition_map = Dict{Tuple{State,AbstractSignal},State}()
    # action_map = Dict{Tuple{State,AbstractSignal},Vector{Union{Nothing,AbstractTransitionAction}}}()
    transition_map = Dict{TransitionPair,Union{Nothing,State}}()
    action_map = Dict{TransitionPair,Vector{Union{Nothing,AbstractTransitionAction}}}()
    active_signals = SignalEvent[]
    return StateManager(valid_states,current_state,valid_signals,transition_map,action_map,active_signals)
end

getstatemanager(SM::StateManager) = SM
getstring(SM::StateManager) = "Manager"

getvalidsignals(target::SignalTarget) = getstatemanager(target).valid_signals
getstates(target::SignalTarget) = getstatemanager(target).valid_states
getstate(target::SignalTarget) = getstatemanager(target).current_state
getcurrentstate(SM::StateManager) = getstatemanager(target).current_state

addsignal!(target::SignalTarget,signal::AbstractSignal) = signal in getstatemanager(target).valid_signals ? nothing : push!(getstatemanager(target).valid_signals,signal)
addsignal!(target::SignalTarget,signal::Symbol) = addsignal!(getstatemanager(target),Signal(signal))
addstate!(target::SignalTarget,state::State) = state in getstatemanager(target).valid_states ? nothing : push!(getstatemanager(target).valid_states,state)
addstate!(target::SignalTarget,state::Symbol) = addstate!(getstatemanager(target),State(state))

# Add valid states
function addstates!(target::SignalTarget,states::Vector{State})
    SM = getstatemanager(target)
    append!(SM.valid_states,states)
end
function addstates!(target::SignalTarget,states::Vector{Symbol})
    SM = getstatemanager(target)
    states = [State(state) for state in states]
    append!(SM.valid_states,states)
end

# Set current state
function setstate(target::SignalTarget,state::State)
    SM = getstatemanager(target)
    @assert state in SM.valid_states
    SM.current_state = state
end
setstate(target::SignalTarget,state::Symbol) = setstate(getstatemanager(target),State(state))

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

function addtransition!(target::SignalTarget,state1::State,signal::AbstractSignal,state2::Union{State,Nothing}; action::Union{Nothing,AbstractTransitionAction} = nothing)
    SM = getstatemanager(target)

    pair = TransitionPair(state1,signal)
    if !(haskey(SM.transition_map,pair))  #If the target does not have the proposed transition
        addstate!(SM,state1)
        addsignal!(SM,signal)

        if state2 != nothing
            addstate!(SM,state2)
        end
        SM.transition_map[pair] = state2

        if action != nothing
            SM.action_map[pair] = [action]
        end
    else
        #If we already have the transition, just add a new action
        if action != nothing
            if length(SM.action_map[pair]) == 0
                SM.action_map[pair] = [action]
            else
                push!(SM.action_map[pair],action)
            end
        end
    end
    return tuple(state1,signal,state2)
end

function addtransition!(target::SignalTarget,transition::Transition;action::Union{Nothing,AbstractTransitionAction} = nothing)
    transition = addtransition!(target,transition[1],transition[2],transition[3],action = action)
    return transition
end

# function hastransition(target::SignalTarget,state1::State,signal::AbstractSignal)
#     SM = getstatemanager(target)
#     #return haskey(SM.transition_map,tuple(state1,signal))
#     if haskey(SM.transition_map,tuple(state1,signal))
#         return true
#     elseif haskey(SM.transition_map,tuple(State(state1.label),signal))
#         return true
#     elseif haskey(SM.transition_map,tuple(State(:any),signal))
#         return true
#     elseif haskey(SM.transition_map,tuple(State(:any),Signal(signal.label,:nothing)))
#         return true
#     else
#         return false
#     end
# end
function hastransition(target::SignalTarget,state1::State,signal::AbstractSignal)
    SM = getstatemanager(target)
    #return haskey(SM.transition_map,tuple(state1,signal))
    for state in [state1,State(state1.label),State(:any)]
        for signal in [signal,Signal(signal.label)]
            pair = TransitionPair(state,signal)
            if haskey(target.transition_map,pair)
                return true
            end
        end
    end
    return false
end

#
#     if haskey(SM.transition_map,TransitionPair(state1,signal))
#         return true
#     elseif haskey(SM.transition_map,tuple(State(state1.label),signal))
#         return true
#     elseif haskey(SM.transition_map,tuple(State(:any),signal))
#         return true
#     elseif haskey(SM.transition_map,tuple(State(:any),Signal(signal.label,:nothing)))
#         return true
#     else
#         return false
#     end
# end

# function addaction!(target::SignalTarget,)
# end

function setaction(target::SignalTarget,transition::Transition,action::AbstractTransitionAction)
    SM = getstatemanager(target)
    pair = TransitionPair(transition[1],transition[2])
    SM.action_map[pair] = action
end

# function hasaction(target::SignalTarget,state1::State,signal::AbstractSignal)
#     SM = getstatemanager(target)
#     return haskey(SM.action_map,tuple(state1,signal))
# end

#match the state and input signal to the best possible transition and action
function matchtransitionpattern(target::SignalTarget,state::State,input_signal::Signal)
    SM = getstatemanager(target)
    found_transition = false
    found_action = false
    new_state = nothing
    actions = nothing
    for state in [state,State(state.label),state_any()]
        for signal in [input_signal,Signal(input_signal.label)]
            pair = TransitionPair(state,signal)
            if haskey(target.transition_map,pair) && found_transition == false
                found_transition = true
                new_state = target.transition_map[pair]
            end
            if haskey(target.action_map,pair) && found_action == false
                found_action = true
                actions = target.action_map[pair]
            end
        end
    end
    return new_state,actions
end

#TODO Figure out a better way to determine if a state manager has a transition
function runtransition!(target::SignalTarget,input_signal::Signal)
    SM = getstatemanager(target)
    start_state = getstate(SM)

    new_state,actions = matchtransitionpattern(target,start_state,input_signal)
    if new_state != nothing
        setstate(SM,new_state)
    end

    if actions != nothing
        for action in actions
            runaction!(input_signal,action)
        end
    else
        @warn "no action for transition $start_state + $input_signal"
    end
end

    #actions = matchactionpattern(target,input_signal,start_state)

    # #Use actual start state and input signal
    # if haskey(SM.transition_map,tuple(start_state,input_signal))
    #     new_state = SM.transition_map[start_state,input_signal]
    #     if new_state !== State(:any)
    #         setstate(SM,new_state)
    #     end
    #     if hasaction(SM,start_state,input_signal)
    #         actions = SM.action_map[start_state,input_signal]
    #         for action in actions
    #             runaction!(input_signal,action)
    #         end
    #     elseif haskey(SM.action_map,tuple(start_state,Signal(input_signal.label)))
    #         actions = SM.action_map[start_state,Signal(input_signal.label)]
    #         for action in actions
    #             runaction!(input_signal,action)
    #         end
    #     else
    #         @warn "no action for $input_signal on $target 1"
    #     end
    #
    # #use generic start state and input signal
    # elseif haskey(SM.transition_map,tuple(State(start_state.label),input_signal))
    #     #TODO correct state setting
    #     #new_state = SM.transition_map[State(start_state.label),input_signal]
    #     # if new_state !== State(:any)
    #     #     setstate(SM,new_state)
    #     # end
    #
    #     if hasaction(SM,State(start_state.label),input_signal)
    #         actions = SM.action_map[State(start_state.label),input_signal]
    #         for action in actions
    #             runaction!(input_signal,action)
    #         end
    #
    #     elseif haskey(SM.action_map,tuple(State(start_state.label),Signal(input_signal.label)))
    #         actions = SM.action_map[State(start_state.label),Signal(input_signal.label)]
    #         for action in actions
    #             runaction!(input_signal,action)
    #         end
    #
    #     else
    #         @warn "no action for $input_signal on $target 2"
    #     end
    #
    # #use :any start state and input signal
    # elseif haskey(SM.transition_map,tuple(State(:any),input_signal))
    #     start_state = State(:any)
    #     if hasaction(SM,State(:any),input_signal)
    #         actions = SM.action_map[start_state,input_signal]
    #         for action in actions
    #             runaction!(input_signal,action)
    #         end
    #     elseif haskey(SM.action_map,tuple(State(start_state.label),Signal(input_signal.label)))
    #         actions = SM.action_map[State(start_state.label),Signal(input_signal.label)]
    #         for action in actions
    #             runaction!(input_signal,action)
    #         end
    #
    #     else
    #         @warn "no action for $input_signal on $target 3"
    #     end
    #
    # #Use :any start state and generic input signal
    # elseif haskey(SM.transition_map,tuple(State(:any),Signal(input_signal.label,:nothing)))
    #     start_state = State(:any)
    #     if hasaction(SM,State(:any),Signal(input_signal.label,:nothing))
    #         actions = SM.action_map[start_state,Signal(input_signal.label,:nothing)]
    #         for action in actions
    #             runaction!(input_signal,action)
    #         end
    #     elseif haskey(SM.action_map,tuple(State(:any),Signal(input_signal.label)))
    #         actions = SM.action_map[State(:any),Signal(input_signal.label)]
    #         for action in actions
    #             runaction!(input_signal,action)
    #         end
    #     else
    #         @warn "no action for $input_signal on $target 4"
    #     end
    # else
    #     error("Target has no transition for state: $(start_state) with signal $(input_signal)")
    # end
#end

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

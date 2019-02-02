#############################################
# State Manager
#############################################
#local_time::Number
#initial_signal::Union{Nothing,AbstractSignal}
mutable struct StateManager <: AbstractStateManager
    valid_states::Vector{State}            #possible states
    current_state::State             #current state
    valid_signals::Vector{AbstractSignal}  #signal the manager recognizes
    transition_map::Dict{Tuple{State,AbstractSignal},State} , # Transition}             #Allowable transitions for this state manager
    action_map::Dict{Tuple{State,AbstractSignal},Action}
    broadcast_map::Dict{AbstractSignal,SignalTarget}
    suppressed_signals::Vector{AbstractSignal}
end

#Constructor
StateManager() = StateManager(State[],State(),Signal[],Dict{Tuple{State,AbstractSignal},Transition}(),nothing,Signal[],0)

getsignals(SM::StateManager) = SM.signals
#getinitialsignal(SM::StateManager) = SM.initial_signal
getstates(SM::StateManager) = SM.states
gettransitions(SM::StateManager) = collect(values(SM.transition_map))
gettransition(SM::StateManager,state::State,signal::AbstractSignal) = SM.transition_map[tuple(state,signal)]
getcurrentstate(SM::StateManager) = SM.current_state
getlocaltime(SM::StateManager) = SM.local_time

addsignal!(SM::StateManager,signal::AbstractSignal) = signal in SM.signals ? nothing : push!(SM.signals,signal)
addsignal!(SM::StateManager,signal::Symbol) = addsignal!(SM,Signal(signal))
addstate!(SM::StateManager,state::State) = state in SM.states ? nothing : push!(SM.states,state)
addstate!(SM::StateManager,state::Symbol) = addstate!(SM,State(state))
suppresssignal!(SM::StateManager,signal::Signal) = push!(SM.suppressed_signals,signal)
unsuppresssignal!(SM::StateManager,signal::Signal) = filter!(x -> x != signal,SM.suppressed_signals)

# Add valid states
function addstates!(SM::StateManager,states::Vector{State})
    append!(SM.states,states)
end
function addstates!(SM::StateManager,states::Vector{Symbol})
    states = [State(state) for state in states]
    append!(SM.states,states)
end

# Set current state
function setcurrentstate(SM::StateManager,state::State)
    @assert state in SM.states
    SM.current_state = state
end
setstate(SM::StateManager,state::Symbol) = setstate(SM,State(state))

# Set valid states
function setvalidstates(SM::StateManager,states::Vector{State})
    @assert SM.current_state in states
    SM.states = states
end
function setvalidstates(SM::StateManager,states::Vector{Symbol})
    states = [State(state) for state in states]
    @assert SM.current_state in states
    SM.states = states
end


const Transition = Tuple{State,AbstractSignal,State}

function addtransition!(SM::StateManager,state1::State,signal::AbstractSignal,state2::State;action = TransitionAction(),targets = SignalTarget[])
    SM.transition_map[tuple(state,signal)] = state2
    SM.action_map[tuple(state,signal)] = action
    SM.broadcast_map[tuple(state,signal)] = targets
end

function addtransition!(SM::StateManager,transition::Transition)
    addsignal!(SM,transition.input_signal)
    addstate!(SM,transition.starting_state)
    addstate!(SM,transition.new_state)
    SM.transition_map[tuple(transition.starting_state,transition.input_signal)] = transition
    return transition
end

function addbroadcasttarget!(SM::StateManager,state1::State,signal::AbstractSignal,output_target::SignalTarget)
    if !(target in transition.output_signal_targets)
        push!(transition.output_signal_targets,target)
    end
end

function addbroadcasttarget!(transition::Transition,target::SignalTarget)
    if !(target in transition.output_signal_targets)
        push!(transition.output_signal_targets,target)
    end
end

function runtransition!(SM::StateManager,input_signal::Signal)
    start_state = getcurrentstate(SM)
    new_state = SM.transition_map[start_state,input_signal])
    setstate(SM,new_state)
    action = SM.action_map[start_state,input_signal]
    return_signal = run!(action)
    return return_signal
end

# function setinitialsignal(SM::StateManager,signal::AbstractSignal)
#     SM.initial_signal = signal
# end

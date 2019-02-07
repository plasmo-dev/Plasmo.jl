#Define a transition
const Transition = Tuple{State,AbstractSignal,State}

#############################################
# Transition Action
#############################################
mutable struct TransitionAction
    func::Function                                  #the function to call
    args::Vector{Any}                               #the function args
    kwargs::Dict{Symbol,Any}                        #possible kwargs
end

#Constructor
TransitionAction(func::Function) = TransitionAction(func,[],Dict(),Vector{Pair{Signal,Float64}}())
TransitionAction(func::Function,args::Vector) = TransitionAction(func,args,Dict(),Vector{Pair{Signal,Float64}}())

#Run transition action
function run_action!(action::TransitionAction) = action.func(action.args...,action.kwargs...)  #run a transition action
#function run!(action::TransitionAction) = action.result = action.func(action.args...,action.kwargs...)  #run a transition action

#############################################
# State Manager
#############################################
#local_time::Number
#initial_signal::Union{Nothing,AbstractSignal}
mutable struct StateManager <: AbstractStateManager
    valid_states::Vector{State}                                               #possible states
    current_state::State                                                      #current state
    valid_signals::Vector{AbstractSignal}                                     #state manager recognizes these signals
    transition_map::Dict{Tuple{State,AbstractSignal},State} , # Transition}           x^+ = f(x,u)
    action_map::Dict{Tuple{State,AbstractSignal},Union{Nothing,TransitionAction}}     #eta^+ = g(eta)
    broadcast_map::Dict{AbstractSignal,Vector{SignalTarget}}                          #y^+ = h(g)
    suppressed_signals::Vector{AbstractSignal}                                #ignore these signals
    active_signals::Vector{SignalEvent}                                       #vector of signal events this state manager has to evaluate
end

#Constructor
function StateManager()
    SM = new()
    SM.valid_states = State[]
    SM.current_state = State()
    SM.valid_signals = Signal[]
    SM.transition_map = Dict{Tuple{State,AbstractSignal},State}()
    SM.action_map = Dict{Tuple{State,AbstractSignal},Union{Nothing,TransitionAction}}()
    #SM.broadcast_map = Dict{AbstractSignal,Vector{SignalTarget}}()
    #SM.suppressed_signals = Signal[]
    SM.active_signals = Signal[]
    return SM
end
#StateManager() = StateManager(State[],State(),Signal[],Dict{Tuple{State,AbstractSignal},Transition}(),nothing,Signal[],0)
getstatemanager(SM::StateManager) = SM

getsignals(SM::StateManager) = SM.signals
getstates(SM::StateManager) = SM.states

gettransitions(SM::StateManager) = [[k[1],k[2],v] for (k,v) in SM.transition_map]

gettransition(SM::StateManager,state::State,signal::AbstractSignal) = [state,signal,SM.transition_map[tuple(state,signal)]]
getcurrentstate(SM::StateManager) = SM.current_state

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
    append!(SM.valid_states,states)
end

# Set current state
function setcurrentstate(SM::StateManager,state::State)
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
    SM.states = states
end

function addtransition!(SM::StateManager,state1::State,signal::AbstractSignal,state2::State; action::Union{Nothing,TransitionAction} = nothing,
    targets::Vector{SignalTarget} = SignalTarget[])
    SM.transition_map[tuple(state,signal)] = state2
    SM.action_map[tuple(state,signal)] = action
    #SM.broadcast_map[tuple(state,signal)] = targets
    return tuple(state1,signal,state2)
end

function addtransition!(SM::StateManager,transition::Transition)
    addstate!(SM,transition[1])
    addsignal!(SM,transition[2])
    addstate!(SM,transition[3])
    SM.transition_map[tuple(transition[1],transition[2])] = transition[3]
    return transition
end

function setaction(SM::StateManager,transition::Transition,action::TransitionAction)
    SM.action_map[tuple(transition[1],transition[2]] = action
end

#Add target to broadcast mapping
# function addbroadcasttarget!(SM::StateManager,state1::State,signal::AbstractSignal,output_target::SignalTarget)
#     if !(target in SM.broadcast_map[tuple(state1,signal)])
#         push!(SM.broadcast_map[tuple(state1,signal)],target)
#     end
# end

function addbroadcasttarget!(SM::StateManager,signal::AbstractSignal,output_target::SignalTarget)
    if !(target in SM.broadcast_map[signal])
        push!(SM.broadcast_map[signal],target)
    end
end

function runtransition!(SM::StateManager,input_signal::Signal)
    start_state = getcurrentstate(SM)
    if hastransition(SM,start_state,input_signal)
        new_state = SM.transition_map[start_state,input_signal])
        setstate(SM,new_state)
        action = SM.action_map[start_state,input_signal]
        run_action!(action)
        #return_signal =
        #return return_signal
    else
        error("State manager has no transition for state: $(start_state) for signal $(input_signal)")
    end
end

#getlocaltime(SM::StateManager) = SM.local_time
# function setinitialsignal(SM::StateManager,signal::AbstractSignal)
#     SM.initial_signal = signal
# end
#getinitialsignal(SM::StateManager) = SM.initial_signal

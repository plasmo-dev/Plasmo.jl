struct State
    label::Symbol
end
State() = State(:null)
State(label::Symbol) = State(label)

#Signal can be an input or output
struct Signal <: AbstractSignal
    label::Symbol
    value::Any  #Attribute, or other value, or even an Array
end
Signal(sym::Symbol) = Signal(sym,nothing)
Signal() = Signal(:empty,nothing)

const SignalTarget = AbstractStateManager

struct Transition
    previous_state::State
    input_signal::Signal
    new_state::State
    action::TransitionAction
    signal_targets::Vector{SignalTarget}
end
Transition() =  Transition(State(),Signal(),State(),TransitionAction(),SignalTarget[])

struct StateManager <: AbstractStateManager
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

function addtransition!(SM::StateManager,state1::State,signal::Signal,state2::State;action = DispatchFunction(),targets = SignalTarget[])
    transition = Transition(state1,signal,state2,action,targets)
    SM.transtion_map[tuple(state1,signal)] = transition
end

function addbroadcasttarget!(trans::Transition,target::SignalTarget)
    push!(trans.signal_targets,target)
end

function runtransition!(SM::StateManager,transition::Transition)
    current_state = getstate(SM)
    if current_state == transition.previous_state
        new_state = transition.new_state
        setstate(SM,new_state)
        return run!(transition.action(transition.signal))  #returns signals
    else
        return nothing
    end
end
# #Signals get sent to a coordinator
# function run_transition!(transition::Transition)
#     signals = transition.action()
#     queue(signals)
# end
#const State = Symbol
#const Transition = Tuple{State,Signal,State}

#@enum state idle = 1 scheduled = 2 computing = 3 synchronizing = 4 error = 5 inactive = 6 active = 7
#Previous State, signal, new state

struct State
    label::Symbol
    value::Any
end
State() = State(:nothing,:nothing)
State(label::Symbol) = State(label,:nothing)
#State(label::Symbol) = State(label)
#TODO Define an ANY state
==(state1::State,state2::State) = ((state1.label == state2.label && state1.value == state2.value) || state1 == :any || state2.label == :any)

state_any() = State(:any)

#Signal for mapping behaviors
struct Signal <: AbstractSignal
    label::Symbol
    value::Any      #Attribute, or other value to compare on
    data::Any       #data associated with the signal
end
Signal(sym::Symbol) = Signal(sym,:nothing,nothing)
Signal(sym::Symbol,value::Any) = Signal(sym,value,nothing)
Signal() = Signal(:nothing,:nothing,nothing)

==(signal1::AbstractSignal,signal2::AbstractSignal) = (signal1.label == signal2.label && signal1.value == signal2.value) ||
(signal1.label == signal2.label && signal1.value == :nothing) || (signal1.label == signal2.label && signal2.value == :nothing)
getlabel(signal::AbstractSignal) = signal.label
getvalue(signal::AbstractSignal) = signal.value
getdata(signal::AbstractSignal) = signal.data

struct TransitionPair
    state::State
    signal::Signal
end

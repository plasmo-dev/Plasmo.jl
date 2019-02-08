struct State
    label::Symbol
    value::Any
end
State() = State(:nothing,nothing)
State(label::Symbol) = State(label,nothing)
#State(label::Symbol) = State(label)
#TODO Define an ANY state
==(state1::State,state2::State) = ((state1.label == state2.label && state1.value == state2.value) || state1.label == :Any || state2.label == :Any)

#Signal for mapping behaviors
struct Signal <: AbstractSignal
    label::Symbol
    value::Any      #Attribute, or other value to compare on
    data::Any       #data associated with the signal
end
Signal(sym::Symbol) = Signal(sym,nothing,nothing)
Signal() = Signal(:nothing,nothing,nothing)

==(signal1::AbstractSignal,signal2::AbstractSignal) = (signal1.label == signal2.label && signal1.value == signal2.value)
getlabel(signal::AbstractSignal) = signal.label
getvalue(signal::AbstractSignal) = signal.value
getdata(signal::AbstractSignal) = signal.data

# #A signal carrying information
# mutable struct DataSignal <: AbstractSignal
#     label::Symbol
#     value::Any              #Attribute, or other value, or even an Array
#     data::Any               #Data the signal may carry.  Can be passed to transition actions.
# end
#
# #NOTE Just use a convert method here?
# Signal(signal::DataSignal) = Signal(signal.label,signal.value)  #Convert data signal to a signal


# getdata(signal::AbstractSignal) = nothing
# getdata(signal::DataSignal) = signal.data

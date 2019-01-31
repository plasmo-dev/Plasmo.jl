####################################
#Print Functions
####################################
function string(signal::AbstractSignal)
    "Signal("*string(signal.label)*" "*string(signal.value)*")"
end
print(io::IO, signal::AbstractSignal) = print(io, string(signal))
show(io::IO, signal::AbstractSignal) = print(io,signal)

function string(state::State)
    string(state.label)*" "*string(state.value)
end
print(io::IO, state::State) = print(io, string(state))
show(io::IO, state::State) = print(io,state)


function string(signalevent::SignalEvent)
    string(signalevent.time)*" "*string(signalevent.signal)*" Target: "*string(signalevent.target)
end
print(io::IO, signalevent::SignalEvent) = print(io, string(signalevent))
show(io::IO, signalevent::SignalEvent) = print(io,signalevent)


function string(manager::StateManager)
    "state manager: current state = "*string(manager.current_state)
end
print(io::IO,manager::StateManager) = print(io, string(manager))
show(io::IO,manager::StateManager) = print(io,manager)

function string(transition::Transition)
    "transition: "*string(transition.starting_state)*" + "*string(transition.input_signal)*" => "*string(transition.new_state)#*"\n output targets: "*
end
print(io::IO,transition::Transition) = print(io, string(transition))
show(io::IO,transition::Transition) = print(io,transition)

####################################
#Print Functions
####################################
function string(signal::AbstractSignal)
    if signal.value == :nothing
        return "Signal("*string(signal.label)*")"
    else
        return "Signal("*string(signal.label)*" "*string(signal.value)*")"
    end
end
print(io::IO, signal::AbstractSignal) = print(io, string(signal))
show(io::IO, signal::AbstractSignal) = print(io,signal)

function string(state::State)
    if state.value == :nothing
        return "("*string(state.label)*")"
    else
        return "("*string(state.label)*" "*string(state.value)*")"
    end
end
print(io::IO, state::State) = print(io, string(state))
show(io::IO, state::State) = print(io,state)


function string(signalevent::SignalEvent)
    string(signalevent.time)*" "*string(signalevent.signal)*" Target: "*string(signalevent.target)
end
print(io::IO, signalevent::SignalEvent) = print(io, string(signalevent))
show(io::IO, signalevent::SignalEvent) = print(io,signalevent)


function string(target::SignalTarget)
    string(getstring(target))
end
print(io::IO,target::SignalTarget) = print(io, string(target))
show(io::IO,target::SignalTarget) = print(io,target)

function string(transition::Transition)
    "Transition: "*string(transition[1])*" + "*string(transition[2])*" => "*string(transition[3])
end
print(io::IO,transition::Transition) = print(io, string(transition))
show(io::IO,transition::Transition) = print(io,transition)

include("../../src/PlasmoWorkflows2/PlasmoWorkflows.jl")

using PlasmoWorkflows

#some actions
function turn_on(signal::AbstractSignal,delay::Number)
    println("turned on")
    return [Pair(Signal(:turned_on),delay)]
end

function turn_off(signal::AbstractSignal,delay::Number)
    println("received signal ",signal)
    println("turned off")
    return [Pair(Signal(:turned_off),delay)]
end

function already_on(signal::AbstractSignal)
    println("already on")
    return [Pair(Signal(:already_on),0)]
end

#Evaluates signals, tracks the event queue clock
coordinator = SignalCoordinator()

#State Machine 1
manager1 = StateManager()
addstate!(manager1,State(:on))
addstate!(manager1,State(:off))
setstate(manager1,:on)

addsignal!(manager1,Signal(:turn_on))
addsignal!(manager1,Signal(:turn_off))

t1 = addtransition!(manager1,State(:on),Signal(:turn_off),State(:off), action = TransitionAction(turn_off,[1]))
t2 = addtransition!(manager1,State(:on),Signal(:turn_on), State(:on), action = TransitionAction(already_on))
t3 = addtransition!(manager1,State(:off),Signal(:turn_on),State(:on), action = TransitionAction(turn_on,[2]))

#State Machine 2
manager2 = StateManager()
addstate!(manager2,State(:active))
addstate!(manager2,:inactive)
addstate!(manager2,:unknown)
setstate(manager2,:inactive)

addsignal!(manager2,:turn_on)
addsignal!(manager2,:turn_off)
addsignal!(manager2,:turned_on)

t4 = addtransition!(manager2,State(:active),Signal(:turn_off),State(:inactive),action = TransitionAction(turn_off,[0]))
t5 = addtransition!(manager2,State(:active),Signal(:turn_on), State(:active), action = TransitionAction(already_on))
t6 = addtransition!(manager2,State(:inactive),Signal(:turn_on),State(:active), action = TransitionAction(turn_on,[1]))
t7 = addtransition!(manager2,State(:active),Signal(:turned_on),State(:unknown))

#Add a broadcast target to transition 2
addbroadcasttarget!(t3,manager2)  #output signal from t2 will hit manager 1

#schedule some signals for the coordinator to evaluate
schedulesignal(coordinator,Signal(:turn_off),manager1,0)
schedulesignal(coordinator,Signal(:turn_on),manager2,3)
schedulesignal(coordinator,Signal(:turn_on),manager1,4)
schedulesignal(coordinator,Signal(:turn_on),manager2,4)

step(coordinator)
step(coordinator)
step(coordinator)
step(coordinator)
#some syntax ideas
#@action(t1,turn_on)
#@transition(manager1, on turn_off => off, action = turn_on, action_arg = 1, output_targets = [manager1])
#

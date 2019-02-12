using Plasmo

#some example actions
function turn_on(input_signal::Signal,squeue::SignalQueue,manager::StateManager,delay::Number)
    println("turned on")
    queuesignal!(squeue,Signal(:turned_on),manager,delay)
end

function turn_off(input_signal::Signal,squeue::SignalQueue,manager::StateManager,signal::AbstractSignal,delay::Number)
    println("received signal",signal)
    println("turned off")
    queuesignal!(squeue,Signal(:turned_off),manager,delay)
end

function already_on()
    println("already on")
end

#Evaluates signals, tracks the event queue clock
queue = SignalQueue()

#State Machine 1
manager1 = StateManager()
addstate!(manager1,State(:on))
addstate!(manager1,State(:off))
setstate(manager1,:on)

addsignal!(manager1,Signal(:turn_on))
addsignal!(manager1,Signal(:turn_off))


# #State Machine 2
manager2 = StateManager()
addstate!(manager2,State(:active))
addstate!(manager2,:inactive)
addstate!(manager2,:unknown)
setstate(manager2,:inactive)

addsignal!(manager2,:turn_on)
addsignal!(manager2,:turn_off)
addsignal!(manager2,:turned_on)

t1 = addtransition!(manager1,State(:on),Signal(:turn_off),State(:off), action = TransitionAction(turn_off,[queue,manager1,Signal(:turn_off),1]))
t2 = addtransition!(manager1,State(:on),Signal(:turn_on), State(:on), action = TransitionAction(already_on))
t3 = addtransition!(manager1,State(:off),Signal(:turn_on),State(:on), action = TransitionAction(turn_on,[queue,manager1,2]))


t4 = addtransition!(manager2,State(:active),Signal(:turn_off),State(:inactive),action = TransitionAction(turn_off,[queue,manager2,0]))
t5 = addtransition!(manager2,State(:active),Signal(:turn_on), State(:active), action = TransitionAction(already_on))
t6 = addtransition!(manager2,State(:inactive),Signal(:turn_on),State(:active), action = TransitionAction(turn_on,[queue,manager2,1]))
t7 = addtransition!(manager2,State(:active),Signal(:turned_on),State(:unknown))

#schedule some signals for the queue to evaluate
queuesignal!(queue,Signal(:turn_off),manager1,0)
queuesignal!(queue,Signal(:turn_on),manager2,3)
queuesignal!(queue,Signal(:turn_on),manager1,4)
queuesignal!(queue,Signal(:turn_on),manager2,4)


step(queue)
step(queue)  #should raise a warning
step(queue)
step(queue)

true

#Shared States
state_idle() = State(:idle)
state_error() = State(:error)
state_inactive() = State(:inactive)


#Node States
state_executing() = State(:executing,:nothing)
state_executing(task::NodeTask) = State(:executing,task)
state_finalizing() = State(:finalizing,:nothing)
state_finalizing(task::NodeTask) = State(:finalizing,task)

#Node Signals
signal_error() = Signal(:error)
signal_error(task::NodeTask) = Signal(:error,task)
signal_inactive() = Signal(:inactive)

#signal_schedule(task::NodeTask,schedule_delay::Float64) = Signal(:schedule,task,schedule_delay)
signal_schedule(task::NodeTask) = Signal(:schedule,task)


#Template signals
signal_execute() = Signal(:execute,:nothing)
signal_finalize() = Signal(:finalize,:nothing)

signal_execute(task::NodeTask) = Signal(:execute,task)
signal_finalize(task::NodeTask) = Signal(:finalize,task)
signal_back_to_idle() = Signal(:back_to_idle)

#Edge States
state_communicating() = State(:communicating)
state_all_received() = State(:all_received)

#Edge Signals
signal_communicate() = Signal(:communicate)

signal_all_received() = Signal(:all_received)

#Attribute Signals
signal_updated() = Signal(:updated,:nothing)
signal_received() = Signal(:received,:nothing)
signal_sent() = Signal(:sent,:nothing)
#signal_communicated() = Signal(:communicated,nothing)


signal_receive() = Signal(:receive) #receive an edge attribute
signal_receive(attribute::EdgeAttribute) = Signal(:receive,attribute)

signal_updated(attribute::NodeAttribute) = Signal(:updated,attribute)
signal_received(attribute::NodeAttribute) = Signal(:received,attribute)
signal_sent(attribute::NodeAttribute) = Signal(:sent,attribute)

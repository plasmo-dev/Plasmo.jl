#Shared States
state_idle() = State(:idle)
state_error() = State(:error)
state_inactive() = State(:inactive)
state_any() = State(:any)

#Node States
state_executing(task::NodeTask) = State(:executing,task)
state_finalizing(task::NodeTask) = State(:finalizing,task)

#Node Signals
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
signal_updated(attribute::NodeAttribute) = Signal(:updated,attribute)
signal_received(attribute::NodeAttribute) = Signal(:received,attribute)
signal_sent(attribute::NodeAttribute) = Signal(:sent,attribute)

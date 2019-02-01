#############################################
# Transition Action
#############################################
mutable struct TransitionAction
    func::Function                                  #the function to call
    args::Vector{Any}                               #the function args
    kwargs::Dict{Any,Any}                           #possible kwargs
    result::Vector{Pair{AbstractSignal,Float64}}    #action returns a signal and time delay
end
TransitionAction() = TransitionAction((signal::AbstractSignal) -> [Pair(Signal(:nothing),0)],[],Dict(),Vector{Pair{Signal,Float64}}())
TransitionAction(func::Function) = TransitionAction(func,[],Dict(),Vector{Pair{Signal,Float64}}())
TransitionAction(func::Function,args::Vector) = TransitionAction(func,args,Dict(),Vector{Pair{Signal,Float64}}())


#NOTE Makes more sense to pass the triggering signal to the transition action
function run!(action::TransitionAction,triggering_signal::AbstractSignal)  #Transition action and signal that triggered it
    action.result = action.func(triggering_signal,action.args...,action.kwargs...)
    return action.result  #will be a vector of signals and times
end

#############################################
# Transition
#############################################
mutable struct Transition
    starting_state::State
    input_signal::AbstractSignal
    new_state::State
    action::TransitionAction
    output_signal_targets::Vector{SignalTarget}
end
Transition() =  Transition(State(),Signal(),State(),TransitionAction(),SignalTarget[])
gettransitionfunction(transition::Transition) = transition.action  #return a dispatch function
settransitionaction(transition::Transition,action::TransitionAction) = transition.action = action

function runtransition(transition::Transition)
end



# #NOTE May not use this run function
# function run!(action::TransitionAction)
#     action.result = action.func(action.args...,action.kwargs...)
#     return action.result  #will be a vector of signals and times
# end

#Node Task
mutable struct DispatchFunction
    func::Function                   #the function to call
    args::Vector{Any}                #the function args
    kwargs::Dict{Any,Any}
    result::Nullable{Any}            #the result after calling the event
end
DispatchFunction() = DispatchFunction(() -> nothing,[],Dict(),nothing)
DispatchFunction(func::Function) =  DispatchFunction(func,[],Dict(),nothing)
run!(dfunc::DispatchFunction) = dfunc.result = dfunc.func(dfunc.args...,dfunc.kwargs...)
getresult(dfunc::DispatchFunction) = get(dfunc.result)

mutable struct TransitionAction
    func::Function                   #the function to call
    args::Vector{Any}                #the function args
    kwargs::Dict{Any,Any}
    result::Vector{Pair{Signal,Float64}}           #action returns a signal
end
TransitionAction() = TransitionAction(() -> [Pair(Signal(:nothing),0)],[],Dict(),Vector{Pair{Signal,Float64}}())
function run!(action::TransitionAction)
    action.result = action.func(action.args...,action.kwargs...)
    return action.result  #will be a vector of signals and times
end


#registeraction(workflow::Workflow)

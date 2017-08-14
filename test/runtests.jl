using Plasmo
using Base.Test

#Test the graph functionality
@test include("graph_tests.jl")

#Test basic model functionality
@test include("model_tests.jl")


#Special Test Problems
@test include("StochPIDTuning_Plasmo.jl")

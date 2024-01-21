module Plasmo

using Requires
using LinearAlgebra
using DataStructures
using SparseArrays
using Graphs
using Printf

using MathOptInterface
const MOI = MathOptInterface
using Reexport
@reexport using JuMP

export OptiGraph, graph_backend, graph_index

abstract type AbstractOptiGraph <: JuMP.AbstractModel end

include("optinode.jl")

include("optiedge.jl")

include("optigraph.jl")

include("moi_backend.jl")

include("moi_aggregate.jl")

include("optimizer_interface.jl")

include("jump_interop.jl")

end
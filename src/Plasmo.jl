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

export OptiGraph

# import JuMP: AbstractModel, AbstractConstraint, AbstractJuMPScalar, ConstraintRef
# import Base: ==, show, print, string, getindex, copy
# import LightGraphs: AbstractGraph, AbstractEdge, Graph
# import DataStructures.OrderedDict
# import Base: ==, string, print, show

abstract type AbstractOptiGraph <: JuMP.AbstractModel end

include("optinode.jl")

include("optiedge.jl")

include("optigraph.jl")

include("graph_backend.jl")

include("optimizer_interface.jl")

include("jump_interop.jl")

end
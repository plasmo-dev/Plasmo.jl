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

export OptiGraph, graph_backend, graph_index,

add_node, add_edge, add_subgraph,

all_nodes, all_edges,

# macros

@optinode, @nodevariables, @linkconstraint

abstract type AbstractOptiGraph <: JuMP.AbstractModel end

include("optinode.jl")

include("node_variables.jl")

include("node_constraints.jl")

include("optiedge.jl")

include("optigraph.jl")

include("moi_backend.jl")

include("moi_aggregate.jl")

include("optimizer_interface.jl")

include("jump_interop.jl")

include("macros.jl")

end
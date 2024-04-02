module Plasmo

using Requires
using LinearAlgebra
using DataStructures
using SparseArrays
using Graphs
using Printf

using MathOptInterface
const MOI = MathOptInterface

using GraphOptInterface
const GOI = GraphOptInterface

using Reexport
@reexport using JuMP

export OptiGraph, graph_backend, graph_index,

add_node, add_edge, add_subgraph,

all_nodes, all_edges,

containing_optigraphs, source_graph,

@optinode, @nodevariables, @linkconstraint

include("core_types.jl")

include("optigraph.jl")

include("optinode.jl")

include("node_variables.jl")

include("node_constraints.jl")

include("optiedge.jl")

include("moi_backend.jl")

include("optimizer_interface.jl")

include("jump_interop.jl")

include("macros.jl")

include("utils.jl")

include("graph_interface/projections.jl")

include("graph_interface/topology.jl")

include("graph_interface/partition.jl")

end
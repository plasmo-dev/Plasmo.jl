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

all_nodes, all_edges, get_subgraphs,

containing_optigraphs, source_graph, assemble_optigraph,

Partition, apply_partition!, aggregate, aggregate!, aggregate_to_depth,

@optinode, @nodevariables, @linkconstraint

include("core_types.jl")

include("node_variables.jl")

include("node_constraints.jl")

include("optigraph.jl")

include("optinode.jl")

include("optiedge.jl")

include("moi_backend.jl")

include("aggregate.jl")

include("optimizer_interface.jl")

include("jump_interop.jl")

include("macros.jl")

include("utils.jl")

include("graph_functions/projections.jl")

include("graph_functions/topology.jl")

include("graph_functions/partition.jl")

end
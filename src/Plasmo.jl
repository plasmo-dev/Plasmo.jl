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

collect_nodes, all_nodes, all_edges, get_subgraphs, local_nodes, local_edges, 

local_subgraphs, num_nodes, num_local_nodes, num_edges, num_local_edges, num_subgraphs, 

num_local_subgraphs,  num_link_constraints,

containing_optigraphs, source_graph, assemble_optigraph,

Partition, apply_partition!, aggregate, aggregate!, aggregate_to_depth,

hyper_projection, edge_hyper_projection, clique_projection,

edge_clique_projection, bipartite_projection,

incident_edges, induced_edges, identify_nodes, identify_edges,

neighborhood, expand,

@optinode, @nodevariables, @linkconstraint

include("core_types.jl")

include("node_variables.jl")

include("optigraph.jl")

include("optinode.jl")

include("optiedge.jl")

include("optielement.jl")

include("backends/moi_backend.jl")

include("aggregate.jl")

include("optimizer_interface.jl")

include("jump_interop.jl")

include("macros.jl")

include("utils.jl")

include("graph_functions/projections.jl")

include("graph_functions/topology.jl")

include("graph_functions/partition.jl")

# extensions
function __init__()
    @require KaHyPar = "2a6221f6-aa48-11e9-3542-2d9e0ef01880" include(
        "graph_functions/kahypar.jl"
    )
end

end
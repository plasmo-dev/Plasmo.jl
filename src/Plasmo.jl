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

export OptiGraph,
    NodeVariableRef,
    graph_backend,
    graph_index,
    add_node,
    get_node,
    add_edge,
    add_subgraph,
    has_edge,
    get_edge,
    get_edge_by_index,
    collect_nodes,
    local_nodes,
    all_nodes,
    local_edges,
    all_edges,
    get_subgraphs,
    local_subgraphs,
    num_local_nodes,
    num_nodes,
    num_local_edges,
    num_edges,
    num_local_subgraphs,
    num_subgraphs,
    local_elements,
    all_elements,
    num_local_variables,
    num_local_constraints,
    local_constraints,
    num_local_link_constraints,
    num_link_constraints,
    local_link_constraints,
    all_link_constraints,
    set_to_node_objectives,
    containing_optigraphs,
    source_graph,
    assemble_optigraph,

    # partition

    Partition,
    apply_partition,
    apply_partition!,
    n_subpartitions,
    all_subpartitions,

    # aggregate

    aggregate,
    aggregate!,
    aggregate_to_depth,

    # projections

    hyper_projection,
    edge_hyper_projection,
    clique_projection,
    edge_clique_projection,
    bipartite_projection,

    # topoology

    incident_edges,
    induced_edges,
    identify_nodes,
    identify_edges,
    neighborhood,
    expand,

    # macros

    @optinode,
    @nodevariables,
    @linkconstraint,

    # other functions

    set_jump_model

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

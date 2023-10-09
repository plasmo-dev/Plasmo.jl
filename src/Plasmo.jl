module Plasmo

using Requires
using LinearAlgebra
using DataStructures
using SparseArrays
using LightGraphs
using Printf

using MathOptInterface
const MOI = MathOptInterface

using Reexport
@reexport using JuMP

import JuMP: AbstractModel, AbstractConstraint, AbstractJuMPScalar, ConstraintRef
import Base: ==, show, print, string, getindex, copy
import LightGraphs: AbstractGraph, AbstractEdge, Graph
import DataStructures.OrderedDict
import Base: ==, string, print, show

export

    #################################
    # OptiGraph
    ################################
    AbstractOptiGraph,
    OptiGraph,
    OptiNode,
    OptiEdge,
    LinkConstraint,
    LinkConstraintRef,
    Partition,
    OptiGraphNLPEvaluator,
    add_node!,
    optinode,
    optinodes,
    all_nodes,
    optinode_by_index,
    num_nodes,
    num_all_nodes,
    optiedge,
    optiedges,
    all_edges,
    optiedge_by_index,
    num_edges,
    num_all_edges,
    add_subgraph!,
    subgraph,
    subgraphs,
    all_subgraphs,
    subgraph_by_index,
    num_subgraphs,
    num_all_subgraphs,
    has_subgraphs,
    optigraph_reference,
    @optinode,
    @linkconstraint,

    # linkconstraints
    linkconstraints,
    all_linkconstraints,
    num_linkconstraints,
    num_all_linkconstraints,
    num_linked_variables,

    # optinode
    jump_model,
    set_model,
    has_model,
    is_set_to_node,
    label,
    set_label,
    attached_node,
    set_attached_node,
    is_node_variable,
    is_linked_variable,

    # graph processing
    incident_edges,
    neighborhood,
    induced_edges,
    expand,
    induced_graph,
    apply_partition!,
    cross_edges,
    cross_edges_not_global,
    hierarchical_edges,
    hierarchical_edges_not_global,
    global_edges,
    graph_depth,
    aggregate,
    aggregate!,

    # model functions
    num_all_variables,
    num_all_constraints,
    has_objective,
    has_nl_objective,
    has_node_objective,
    set_node_primals,
    set_node_duals,
    set_node_status,

    # hypergraph functions
    in_degree,
    out_degree,
    all_neighbors,
    induced_subgraph,
    neighbors,
    adjacency_matrix,
    incidence_matrix,

    # graph projections
    bipartite_graph,
    clique_graph,
    hyper_graph,
    edge_graph,
    edge_hyper_graph

#Abstract Types
abstract type AbstractOptiGraph <: JuMP.AbstractModel end
abstract type AbstractOptiEdge end
abstract type AbstractLinkConstraintRef end
abstract type AbstractLinkConstraint <: JuMP.AbstractConstraint end

include("graph_representations/hypergraph.jl")

include("graph_representations/bipartitegraph.jl")

include("graph_representations/cliquegraph.jl")

include("moi_backend_node.jl")

include("optinode.jl")

include("optiedge.jl")

include("moi_backend_graph.jl")

include("optigraph.jl")

include("macros.jl")

include("aggregate.jl")

include("aggregate_utils.jl")

include("optimizer_interface.jl")

include("graph_projections.jl")

include("graph_functions.jl")

include("nlp_evaluator.jl")

include("partition.jl")

include("structure.jl")

function __init__()
    @require KaHyPar = "2a6221f6-aa48-11e9-3542-2d9e0ef01880" include(
        "partition_interface/kahypar.jl"
    )
end

end

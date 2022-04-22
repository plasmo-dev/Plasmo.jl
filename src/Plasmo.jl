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
import Base: ==,show,print,string,getindex,copy
import LightGraphs:AbstractGraph,AbstractEdge,Graph
import DataStructures.OrderedDict
import Base: ==,string,print,show

export

#################################
# OptiGraph
################################
AbstractOptiGraph, OptiGraph, ModelGraph,

OptiNode, OptiEdge, LinkConstraint, LinkConstraintRef, Partition,

#deprecated exports
ModelNode, LinkEdge, getnumnodes, getnumedges, getmodel,

#nlp evaluator
OptiGraphNLPEvaluator,

#optigraphs
add_node!, getnode, getnodes, all_node, all_nodes, find_node, num_nodes, num_all_nodes,

getedge, getoptiedge, getedges,  getoptiedges, all_edge, all_edges,

find_edge, num_optiedges, num_all_optiedges,

add_subgraph!, getsubgraph, getsubgraphs, all_subgraph, all_subgraphs, num_subgraphs, has_subgraphs,

optinodes, optiedges, all_optinodes, all_optiedges,

incident_edges, neighborhood, induced_edges, expand, induced_graph, apply_partition!,

linking_edges, hierarchical_edges,

linkconstraints, all_linkconstraints, num_all_variables, num_linked_variables,

num_all_constraints, num_linkconstraints, num_all_linkconstraints, num_all_subgraphs,

has_objective, has_nl_objective, has_node_objective,

optigraph_reference,

#node interface
jump_model, set_model, has_model, is_set_to_node, getlabel, set_label, attached_node,

set_attached_node, is_node_variable, is_linked_variable,

# Aggregation
aggregate, aggregate!,

# Model Interface
set_node_primals, set_node_duals, set_node_status,

######################################
# HYPERGRAPH INTERFACE
######################################
#
set_graph_backend, graph_backend_data, graph_backend,

# Hypergraph functions
in_degree, out_degree, get_supporting_nodes, get_supporting_edges,

get_connected_to, get_connected_from,

in_neighbors, out_neighbors, neighbors, has_edge, in_edges, out_edges,

adjacency_matrix, incidence_matrix, graph_structure,

# Hypergraph Projections
bipartite_graph, clique_graph, hyper_graph, edge_graph, edge_hyper_graph,

gethyperedge, gethyperedges,

#macros
@optinode, @linkconstraint,

#deprecated
@node, @NLnodeconstraint, @NLnodeobjective,

nodevalue, nodedual, linkdual, gethypergraph, combine, make_subgraphs!


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

include("nlp_macro.jl")

include("nlp_evaluator.jl")

include("partition.jl")

include("structure.jl")

function __init__()
    @require KaHyPar = "2a6221f6-aa48-11e9-3542-2d9e0ef01880" include("partition_interface/kahypar.jl")
end

end

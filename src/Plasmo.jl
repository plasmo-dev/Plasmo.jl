module Plasmo

using Requires
using LinearAlgebra
using DataStructures
using SparseArrays

using MathOptInterface
const MOI = MathOptInterface

using Reexport
@reexport using JuMP

import JuMP: AbstractModel, AbstractConstraint, AbstractJuMPScalar, ConstraintRef
import Base: ==,show,print,string,getindex,copy
import LightGraphs:AbstractGraph,AbstractEdge,Graph
import DataStructures.OrderedDict

#Model Graph
export

#################################
# OptiGraph
################################
AbstractOptiGraph, OptiGraph, ModelGraph,

#ModelNode and LinkEdge
OptiNode,OptiEdge,
ModelNode,LinkEdge,

getsubgraph,getsubgraphs,all_subgraphs,

getnode, getnodes, all_nodes, find_node,

add_node!,add_edge!,add_subgraph!,

getedge, getedges, all_edges, find_edge,

getnumnodes, getnumedges,

#Graph Functions
incident_edges, neighborhood, induced_edges, expand,

#LinkVariable and LinkConstraint
LinkConstraint,LinkConstraintRef,

#Partition
Partition,

#Solvers/Optimizers
AbstractGraphOptimizer,

# solve handles
optimize!,

# OptiGraph checks
has_objective,has_NLobjective, has_NLlinkconstraints, has_subgraphs, has_model,

num_linkconstraints, num_optiedges, num_nodes,

num_all_optiedges, num_all_variables, num_all_constraints, num_all_linkconstraints,

# OptiGraph getters
getoptiedge, getoptiedges, getmodel,

incidence_matrix, getlinkconstraints, getattribute,

all_linkconstraints,

# OptiGraph setters
set_model, set_optimizer, reset_model, setattribute, set_attached_node,

# Variable functions
is_nodevariable, is_linked_variable,

# Aggregation
make_subgraphs!,aggregate,combine,

# Distribute
distribute,

# solution management
nodevalue, nodedual, linkdual,

# extras, plotting, etc...
plot, spy,

#export to file
export_graph,

######################################
# HYPERGRAPH INTERFACE
######################################
HyperGraph, HyperEdge, HyperNode,

# Hypergraph getters
gethypergraph, gethyperedge, gethyperedges,

# Hypergraph adders
add_hypernode!,add_hyperedge!,

# Hypergraph functions
in_degree, out_degree, get_supporting_nodes, get_supporting_edges, get_connected_to,get_connected_from,

in_neighbors,out_neighbors,neighbors, has_edge, in_edges, out_edges,

# Hypergraph Projections
BipartiteGraph,

copy_graph,

#Projections
clique_expansion, star_expansion,

#macros
@node, @optinode, @linkconstraint,

@NLnodeconstraint, @NLnodeobjective

#TODO
#@NLlinkconstraint,


#Abstract Types
abstract type AbstractOptiGraph <: JuMP.AbstractModel end
abstract type AbstractOptiEdge end
abstract type AbstractLinkConstraintRef end
abstract type AbstractGraphOptimizer end
abstract type AbstractLinkConstraint <: JuMP.AbstractConstraint end

include("hypergraphs/hypergraph.jl")

include("hypergraphs/projections.jl")

include("optinode.jl")

include("optiedge.jl")

include("optigraph.jl")

include("macros.jl")

include("partition.jl")

include("combine.jl")          #An aggregated JuMP model

include("copy.jl")

include("optimizer_interface.jl")              #Aggregate and solve with an MOI Solver

include("graph_interface.jl")

include("graph_functions.jl")


function __init__()
    @require Plots = "91a5bcdd-55d7-5caf-9e0b-520d859cae80" include("extras/plots.jl")
    @require KaHyPar = "2a6221f6-aa48-11e9-3542-2d9e0ef01880" include("extras/kahypar.jl")
end

end

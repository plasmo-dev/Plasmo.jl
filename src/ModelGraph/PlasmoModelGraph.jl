module PlasmoModelGraph

using ..PlasmoGraphBase
using Requires

import ..PlasmoGraphBase:getedge,getnodes,getedges

import JuMP
import JuMP:AbstractModel, AbstractConstraint, AbstractJuMPScalar, Model, ConstraintRef
import Base.==


#Model Graph Constructs
export AbstractModelGraph, ModelGraph, ModelTree, ModelNode, LinkingEdge, LinkConstraint,
JuMPGraphModel, JuMPGraph,BipartiteGraph,UnipartiteGraph,PipsTree,

#Solver Constructs
BendersSolver,LagrangeSolver,PipsSolver,

load_pips,

#re-export base functions
add_node!,getnodes,getedges,collectnodes,

#Model functions
setmodel,setsolver,setmodel!,resetmodel,is_nodevar,getmodel,getsolver,hasmodel,
getnumnodes, getobjectivevalue, getinternalgraphmodel,getroot,add_master!,

#Link Constraints
addlinkconstraint, getlinkreferences, getlinkconstraints, getsimplelinkconstraints, gethyperlinkconstraints, get_all_linkconstraints,


#Graph Transformation functions
aggregate!,create_aggregate_model,create_partitioned_model_graph,create_lifted_model_graph,getbipartitegraph,getunipartitegraph,partition,label_propagation,create_pips_tree,

#JuMP Interface functions
buildjumpmodel!, create_jump_graph_model,
getgraph,getnodevariables,getnodevariable,getnodevariablemap,getnodeobjective,getnodeconstraints,getnodedata,is_graphmodel,

#solve handles
solve_jump,pipsnlp_solve,dsp_solve,bendersolve,solve,

#Solution management
getsolution,setsolution,setvalue,getvalue,

#macros
@linkconstraint,@getconstraintlist

#Abstract Types
abstract type AbstractModelGraph <: AbstractPlasmoGraph end
abstract type AbstractModelNode <: AbstractPlasmoNode end
abstract type AbstractLinkingEdge  <: AbstractPlasmoEdge end
abstract type AbstractPlasmoSolver end

include("linkmodel.jl")

include("modelgraph.jl")

include("modelnode.jl")

include("modeledge.jl")

include("solve.jl")

include("solution.jl")

include("macros.jl")

include("aggregation.jl")

include("partition.jl")

include("graph_transformations/modeltree.jl")

include("graph_transformations/pipstree.jl")

include("graph_transformations/partite_graphs.jl")

include("graph_transformations/graph_transformation.jl")

#Plasmo Solvers
include("plasmo_solvers/plasmo_solvers.jl")

#External Solver Interfaces
include("solver_interfaces/wrapped_solvers.jl")

include("solver_interfaces/plasmoPipsNlpInterface3.jl")
using .PlasmoPipsNlpInterface3
# load_pips()
#
# load_dsp()

end

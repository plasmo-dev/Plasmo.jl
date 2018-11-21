module PlasmoModelGraph

using ..PlasmoGraphBase

import ..PlasmoGraphBase:getedge

import JuMP
import JuMP:AbstractModel, AbstractConstraint, AbstractJuMPScalar, Model, ConstraintRef
import Base.==


#Model Graph Constructs
export AbstractModelGraph, ModelGraph, ModelTree, ModelNode, LinkingEdge, LinkConstraint,
JuMPGraphModel, JuMPGraph,

#Solver Constructs
BendersSolver,

#re-export base functions
add_node!,getnodes,collectnodes,

#Model functions
setmodel,setsolver,setmodel!,resetmodel,is_nodevar,getmodel,hasmodel,
getnumnodes, getobjectivevalue, getinternalgraphmodel,

#Link Constraints
addlinkconstraint, getlinkreferences, getlinkconstraints, getsimplelinkconstraints, gethyperlinkconstraints, get_all_linkconstraints,


#Graph Transformation functions
aggregate!,create_aggregate_model,create_partitioned_model_graph,create_lifted_model_graph,

#JuMP Interface functions
buildjumpmodel!, create_jump_graph_model,
getgraph,getnodevariables,getnodevariable,getnodevariablemap,getnodeobjective,getnodeconstraints,getnodedata,is_graphmodel,

#solve handles
solve_jump,pipsnlp_solve,dsp_solve,solve,

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

include("modeltree.jl")

include("solve.jl")

include("solution.jl")

include("macros.jl")

include("aggregation.jl")

#Plasmo Solvers
include("plasmo_solvers/plasmo_solvers.jl")


#External Solver Interfaces

#load PIPS-NLP if the library can be found
if  !isempty(Libdl.find_library("libparpipsnlp"))
    include("solver_interfaces/plasmoPipsNlpInterface.jl")
    using .PlasmoPipsNlpInterface
else
    pipsnlp_solve(Any...) = throw(error("Could not find a PIPS-NLP installation"))
end

#load DSP if the library can be found
if !isempty(Libdl.find_library("libDsp"))
    include("solver_interfaces/plasmoDspInterface.jl")
    using .PlasmoDspInterface
else
    dsp_solve(Any...) = throw(error("Could not find a DSP installation"))
end

end

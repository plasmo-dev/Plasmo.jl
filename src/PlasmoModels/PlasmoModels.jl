module PlasmoModels

using ..PlasmoGraphBase

import JuMP
import JuMP:AbstractModel, AbstractConstraint, AbstractJuMPScalar, Model, ConstraintRef

#Model Graph Constructs
export ModelGraph, ModelNode, LinkingEdge,LinkConstraint,

#Model functions
setmodel,setsolver,setmodel!,resetmodel,is_nodevar,getmodel,hasmodel,

addlinkconstraint, getlinkreferences,getlinkconstraints, getsimplelinkconstraints, gethyperlinkconstraints,get_all_linkconstraints,
getnumnodes,
getobjectivevalue,
getinternalgraphmodel,

#Graph Manipulation Functions
aggregate!,create_partitioned_model_graph,

#JuMP Interface functions
JuMPGraph,buildjumpmodel!,JuMPGraphModel,create_jump_graph_model,
getgraph,getnodevariables,getnodevariable,getnodevariablemap,getnodeobjective,getnodeconstraints,getnodedata,is_graphmodel,

#solve handles
solve_jump,pipsnlp_solve,dsp_solve,solve,

#Solution management
getsolution,setsolution,setvalue,

#macros
@linkconstraint,@getconstraintlist

abstract type AbstractModelGraph <: AbstractPlasmoGraph end
abstract type AbstractModelNode <: AbstractPlasmoNode end
abstract type AbstractLinkingEdge  <: AbstractPlasmoEdge end

include("linkmodel.jl")

include("modelgraph.jl")

include("solve.jl")

include("solution.jl")

include("macros.jl")

include("aggregation.jl")

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

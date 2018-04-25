#  Copyright 2018, Jordan Jalving, Yankai Cao, Victor Zavala, and contributors
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at http://mozilla.org/MPL/2.0/.
#############################################################################
#_precompile_(true)

module Plasmo

using Compat

using PlasmoGraphBase
import PlasmoGraphBase.getnodes

import JuMP
import JuMP:AbstractModel, AbstractConstraint, AbstractJuMPScalar, Model, ConstraintRef

export ModelGraph, ModelNode, LinkingEdge,

LinkConstraint,

#Model functions
setmodel,setsolver,setmodel!,resetmodel,

is_nodevar,

getmodel,hasmodel,

addlinkconstraint, getlinkreferences,getlinkconstraints, getsimplelinkconstraints, gethyperlinkconstraints,get_all_linkconstraints,
getnumnodes,

getobjectivevalue,

getinternalgraphmodel,

#JuMP Interface functions
JuMPGraph,buildjumpmodel!,
#Internal JuMP models (when using JuMP solvers to solve the graph)
JuMPGraphModel,create_jump_graph_model,
#Try to make these work with Base JuMP commands
getgraph,getnodevariables,getnodevariable,getnodevariablemap,getnodeobjective,getnodeconstraints,getnodedata,is_graphmodel,

#solve handles
solve_jump,pipsnlp_solve,dsp_solve,solve,

#Solution management
getsolution,

setsolution,setvalue,

#macros
@linkconstraint,@getconstraintlist

abstract type AbstractModelGraph <: AbstractPlasmoGraph end
abstract type AbstractModelNode <: AbstractPlasmoNode end
abstract type AbstractLinkingEdge  <: AbstractPlasmoEdge end

include("linkmodel.jl")

include("modelgraph.jl")

include("solve.jl")
#
include("solution.jl")
#
include("macros.jl")
#
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

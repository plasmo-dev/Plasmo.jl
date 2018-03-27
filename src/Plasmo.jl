#  Copyright 2017, Jordan Jalving, Yankai Cao, Victor Zavala, and contributors
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at http://mozilla.org/MPL/2.0/.
#############################################################################

#_precompile_(true)

module Plasmo

using Compat

using PlasmoGraphBase
import JuMP
import JuMP:AbstractModel, AbstractConstraint, AbstractJuMPScalar, Model, ConstraintRef

export ModelGraph, ModelNode, LinkingEdge,


#Model functions
setmodel,resetmodel,

is_nodevar,

getmodel,hasmodel,

addlinkconstraint, getlinkconstraints,getobjectivevalue,

buildserialmodel,

getinternalgraphmodel,


#Internal JuMP models (when using JuMP solvers to solve the graph)
FlatModel,create_flat_model,
#Try to make these work with Base JuMP commands
getgraph,getnodevariables,getnodeobjective,getnodeconstraints,getnodedata,is_graphmodel,

solve,

#Solution management
getsolution,

setsolution,setvalue,

#macros
@linkconstraint,@getconstraintlist

abstract type AbstractModelGraph <: AbstractPlasmoGraph end
abstract type AbstractModelNode <: AbstractPlasmoNode end
abstract type AbstractLinkingEdge  <: AbstractPlasmoEdge end

include("linkconstraint.jl")

include("modelgraph.jl")

# include("solve.jl")
#
# include("solution.jl")
#
# include("macros.jl")
#
# #load PIPS-NLP if the library can be found
# if  !isempty(Libdl.find_library("libparpipsnlp"))
#     include("solver_interfaces/plasmoPipsNlpInterface.jl")
#     using .PlasmoPipsNlpInterface
#     export pipsnlp_solve
# end
#
# #load DSP if the library can be found
# if !isempty(Libdl.find_library("libDsp"))
#     include("solver_interfaces/plasmoDspInterface.jl")
#     using .PlasmoDspInterface
#     export dsp_solve
# end


end

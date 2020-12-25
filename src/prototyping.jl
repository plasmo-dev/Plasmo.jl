using JuMP
using MathOptInterface
using Ipopt
using DataStructures
using Plasmo

const MOI = MathOptInterface
include("moi.jl")

m1 = Model()
set_optimizer(m1,Ipopt.Optimizer)
@variable(m1,x[1:5] >= 0)
@variable(m1,y[1:5] >= 1)
@constraint(m1,sum(x) == 10)
@constraint(m1,sum(y) == 5)
@objective(m1,Min,sum(x))
src1 = backend(m1)

m2 = Model()
@variable(m2,x[1:5] >= 0)
@variable(m2,y[1:5] >= 1)
@constraint(m2,sum(y[1:5]) + sum(x[1:5]) == 10)
@objective(m2,Min,sum(x))
src2 = backend(m2)

######################################
m3 = Model()
@variable(m3,x1[1:5] >= 0)
@variable(m3,y1[1:5] >= 1)
@constraint(m3,sum(x1) == 10)
@constraint(m3,sum(y1) == 5)
@variable(m3,x2[1:5] >= 0)
@variable(m3,y2[1:5] >= 1)
@constraint(m3,sum(y2[1:5]) + sum(x2[1:5]) == 10)
@objective(m3,Min,sum(x1) + sum(x2))
######################################

#We can copy models directly into an optimizer
optimizer = Ipopt.Optimizer()

#Setup an MOI model for the destination model.  This could be the optigraph MOI model
caching_mode = MOIU.AUTOMATIC
universal_fallback = MOIU.UniversalFallback(MOIU.Model{Float64}())
caching_opt = MOIU.CachingOptimizer(universal_fallback,caching_mode)
dest = caching_opt
MOIU.reset_optimizer(dest, optimizer)


srces = [src1,src2]
idxmaps = []
for src in srces
    vis_src = MOI.get(src, MOI.ListOfVariableIndices())   #returns vector of MOI.VariableIndex

    #idxmap maps src => dest variable and contraint indices
    idxmap = MOI.Utilities.index_map_for_variable_indices(vis_src)
    push!(idxmaps,idxmap)

    copy_names = false
    filter_constraints = nothing

    # The `NLPBlock` assumes that the order of variables does not change (#849)
    if MOI.NLPBlock() in MOI.get(src, MOI.ListOfModelAttributesSet())
        constraint_types = MOI.get(src, MOI.ListOfConstraints())

        single_variable_types = [S for (F, S) in constraint_types if F == MOI.SingleVariable]
        vector_of_variables_types = [S for (F, S) in constraint_types if F == MOI.VectorOfVariables]

        vector_of_variables_not_added = [MOI.get(src, MOI.ListOfConstraintIndices{MOI.VectorOfVariables, S}()) for S in vector_of_variables_types]
        single_variable_not_added = [MOI.get(src, MOI.ListOfConstraintIndices{MOI.SingleVariable, S}()) for S in single_variable_types]

    else #this sets up idxmap
        #this collects the variable set types that destination model supports
        vector_of_variables_types, _, vector_of_variables_not_added,
        single_variable_types, _, single_variable_not_added =
        MOI.Utilities.try_constrain_variables_on_creation(dest, src, idxmap, MOI.add_constrained_variables, MOI.add_constrained_variable)
    end

    #Copy free variables
    MOI.Utilities.copy_free_variables(dest, idxmap, vis_src, MOI.add_variables)

    # Copy variable attributes
    #MOI.Utilities.pass_attributes(dest, src, copy_names, idxmap, vis_src)

    # Copy model attributes? (e.g. objective function)
    #MOI.Utilities.pass_attributes(dest, src, copy_names, idxmap)

    # Copy constraints
    MOI.Utilities.pass_constraints(dest, src, copy_names, idxmap,
                     single_variable_types, single_variable_not_added,
                     vector_of_variables_types, vector_of_variables_not_added,
                     filter_constraints=filter_constraints)


end

#Get solution from optimizer
vis_dest = MOI.get(dest,MOI.ListOfVariableIndices())
cons = MOI.get(dest,MOI.ListOfConstraints())

cis_dest = []
for con in cons
    F = con[1]
    S = con[2]
    append!(cis_dest,MOI.get(dest,MOI.ListOfConstraintIndices{F,S}()))
end

#TODO Set objective function for backend model

MOI.optimize!(dest)
MOI.get(dest, MOI.VariablePrimal(), vis_dest)


sol_primal = OrderedDict(zip(vis_dest,MOI.get(dest, MOI.VariablePrimal(), vis_dest[1:10])))
sol_dual = OrderedDict(zip(cis_dest,MOI.get(dest, MOI.ConstraintDual(), cis_dest[1:12])))

#Set primal values for each JuMP model using a custom optimizer
node_optimizer = NodeOptimizer(src1)
#TODO: Set solutions based on index maps
node_optimizer.var_values = sol_primal
node_optimizer.var_duals = sol_dual

src1_vis = MOI.get(node_optimizer,MOI.ListOfVariableIndices())
vals = MOI.get(node_optimizer, MOI.VariablePrimal(), src1_vis[1])
m2.moi_backend = node_optimizer

#This works
println(value.(m2[:x]))
println(value.(m2[:y]))




#TODO: Bridge LinkConstraints into an MOI backend
#Meta-algorithms would still use LinkingConstraints on the algorithm side
#LinkingConstraint --> ScalarConstraint

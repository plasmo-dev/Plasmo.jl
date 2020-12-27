using JuMP
using MathOptInterface
using Ipopt
using DataStructures
using Plasmo

const MOI = MathOptInterface
const MOIB = MathOptInterface.Bridges
include("moi.jl")

m1 = Model()
@variable(m1,x[1:5] >= 2)
@variable(m1,y[1:5] >= 1)
@constraint(m1,ref1,sum(x) == 10)
@constraint(m1,ref2,sum(y) == 5)
@objective(m1,Min,sum(x))
src1 = backend(m1)
set_optimizer(m1,Ipopt.Optimizer)

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
#optimizer = Ipopt.Optimizer()

#Setup an MOI model for the destination model.  This could be the optigraph MOI model
caching_mode = MOIU.AUTOMATIC
universal_fallback = MOIU.UniversalFallback(MOIU.Model{Float64}())
caching_opt = MOIU.CachingOptimizer(universal_fallback,caching_mode)
dest = caching_opt
MOIU.reset_optimizer(dest,Ipopt.Optimizer())


srces = MOI.ModelLike[src1,src2]
idxmaps = MOIU.IndexMap[]
for src in srces
    idx_map = append_to_backend!(dest, src, false;filter_constraints=nothing)
    push!(idxmaps,idx_map)#
    #return mapping of dest to each src?
end

#Constraints in dest model
cons = MOI.get(dest,MOI.ListOfConstraints())
cis_dest = []
for con in cons
    F = con[1]
    S = con[2]
    append!(cis_dest,MOI.get(dest,MOI.ListOfConstraintIndices{F,S}()))
end

_set_sum_of_affine_objectives!(dest,srces,idxmaps)

MOI.optimize!(dest)


vis_dest = MOI.get(dest,MOI.ListOfVariableIndices())
MOI.get(dest, MOI.VariablePrimal(), vis_dest)
sol_primal_m1 = OrderedDict(zip(vis_dest,MOI.get(dest, MOI.VariablePrimal(), vis_dest[1:10])))
sol_primal_m2 = OrderedDict(zip(vis_dest,MOI.get(dest, MOI.VariablePrimal(), vis_dest[11:20])))
#sol_dual = OrderedDict(zip(cis_dest,MOI.get(dest, MOI.ConstraintDual(), cis_dest[1:12])))

##TODO: Set solutions using index maps
node_optimizers = []
for (src,idxmap) in zip(srces,idxmaps)
    vars = MOI.get(src,MOI.ListOfVariableIndices())
    dest_vars = MOI.VariableIndex[idxmap[var] for var in vars]

    con_list = MOI.get(src,MOI.ListOfConstraints())

    cons = MOI.ConstraintIndex[]
    dest_cons = MOI.ConstraintIndex[]

    for FS in con_list
        F = FS[1]
        S = FS[2]
        con = MOI.get(src,MOI.ListOfConstraintIndices{F,S}())
        dest_con = getindex.(Ref(idxmap),con)
        append!(cons,con)
        append!(dest_cons,dest_con)
    end

    #Get values
    primals = OrderedDict(zip(vars,MOI.get(dest,MOI.VariablePrimal(),dest_vars)))

    #These need to be constraint indices
    duals = OrderedDict(zip(cons,MOI.get(dest,MOI.ConstraintDual(),dest_cons)))

    #Wrap the backend with a node_optimizer backend
    node_optimizer = NodeOptimizer(src)
    node_optimizer.primals = primals
    node_optimizer.duals = duals
    push!(node_optimizers,node_optimizer)
end

m1.moi_backend = node_optimizers[1]
m2.moi_backend = node_optimizers[2]

#This works!
println(value.(m1[:x]))
println(value.(m1[:y]))


#Set primal values for each JuMP model using a custom optimizer
# node_optimizer = NodeOptimizer(src1)
# node_optimizer.var_values = sol_primal
# node_optimizer.var_duals = sol_dual

# src1_vis = MOI.get(node_optimizer,MOI.ListOfVariableIndices())
# vals = MOI.get(node_optimizer, MOI.VariablePrimal(), src1_vis[1])
#TODO: LinkConstraints into an MOI backend
#Meta-algorithms would still use LinkingConstraints on the algorithm side
#LinkingConstraint --> ScalarConstraint
#USe idxmaps to create destination constraints for a caching optimizer

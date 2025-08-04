using Plasmo
using Distributed
using DistributedArrays
using JuMP
using HiGHS
using Ipopt

if nprocs() == 1
    addprocs(1)
end

@everywhere begin
    using Revise
    using Plasmo, JuMP, Distributed, HiGHS, Ipopt, DistributedArrays
end

# Instantiate optigraph
rg = Plasmo.RemoteOptiGraph(worker=2)

@optinode(rg, n1)
@optinode(rg, n2)

@variable(n1, x)
@variable(n1, y)
@variable(n2, z >= 0)

# can query all variables on a graph
all_vars = JuMP.all_variables(rg)

@linkconstraint(rg, lc1, x + rg[:n2][:z] <= 1)

@constraint(n1, n1_con, x + y <= 2); #linear constraint
@constraint(n1, x^2 + y <= 4); # quadratic constraint
@constraint(n1, cos(x) + y^2*x >= 1); #nonlinear constraint

# test naming of expressions on nodes and on graphs
@expression(n1, n1_expr, x + 2 * y)
@expression(rg, rg_expr, x + y + z)

fix(x, 0)

@objective(rg, Min, x + sin(y) + z^2)

set_optimizer(rg, Ipopt.Optimizer)

optimize!(rg)

remote_obj = JuMP.objective_function(rg)

# Define another graph and add nodes
rg2 = Plasmo.RemoteOptiGraph(worker = 2)

@optinode(rg2, n3)
@optinode(rg2, n4)

@variable(n3, x3)
@variable(n3, y3)
@variable(n4, z4)

# Add subgraphs to `rg` using two different methods
Plasmo.add_subgraph(rg, rg2)
rg3 = Plasmo.add_subgraph(rg, worker = 2)

@optinode(rg3, n5)
@variable(n5, x5)

@linkconstraint(rg, x + x3 + rg3[:n5][:x5] == 0);
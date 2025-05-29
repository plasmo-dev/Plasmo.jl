using Revise

using Plasmo
using Distributed
using JuMP
using HiGHS
using Ipopt

if nprocs() == 1
    addprocs(1)
end

@everywhere begin
    using Revise
    using Plasmo, JuMP, Distributed, HiGHS, Ipopt
end

# Instantiate optigraph
rg = Plasmo.RemoteOptiGraph(worker=2)

@optinode(rg, n1)
@optinode(rg, n2)

@variable(n1, x)
@variable(n1, y)
@variable(n2, z)

# can query all variables on a graph
all_vars = JuMP.all_variables(rg)

# Defined RemoteAffExpr made up of RemoteVariableRefs
a = Plasmo.RemoteAffExpr(0.)
# Can update these expressions like normal
JuMP.add_to_expression!(a, x + y)

# @linkconstraint works for adding edges; however, this display does not work correctly
lc = @linkconstraint(rg, x + rg[:n2][:z] <= 1);

@constraint(n1, x + y <= 2);
@constraint(n1, x^2 + y <= 4);
@constraint(n1, sin(x) + y^2*x >= 1);

@objective(n1, Min, x)
@objective(rg, Min, x + sin(y) + z^2)

set_optimizer(rg, Ipopt.Optimizer)

optimize!(rg)

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

println("Success")

# TODO: Need to define the objective on remotes
# TODO: Need to get @constraint and @objective to work; 
# TODO: Need to figure out a way to port a function to a separate worker to add to an optigraph

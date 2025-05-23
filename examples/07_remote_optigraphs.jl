using Revise

using Plasmo
using Distributed
using JuMP

# Instantiate optigraph
rg = Plasmo.RemoteOptiGraph()

# Optional second argument for node name; improves display and makes querying easier
# Next week I will work on enabling the @optinode macro
n1 = add_node(rg)
n2 = add_node(rg, :n2)

# Add variables; easiest to access if the symbol is passed for a name
# Next week I will work on enabling the @variable macro
# These return RemoteVariableRefs
x = Plasmo.add_variable(n1, :x)
y = Plasmo.add_variable(n1, :y)
z = Plasmo.add_variable(n2, :z)

# can query all variables on a graph
all_vars = JuMP.all_variables(rg)

# Defined RemoteAffExpr made up of RemoteVariableRefs
a = Plasmo.RemoteAffExpr(0.)
# Can update these expressions like normal
JuMP.add_to_expression!(a, x + y)

# @linkconstraint works for adding edges; however, this display does not work correctly
lc = @linkconstraint(rg, x + rg[:n2][:z] <= 1);


if nprocs() == 1
    addprocs(1)
end

@everywhere begin
    using Revise
    using Plasmo, JuMP, Distributed
end

# Define another graph and add nodes
rg2 = Plasmo.RemoteOptiGraph(worker = 2)
n3 = add_node(rg2)
n4 = add_node(rg2, :n4)
x2 = Plasmo.add_variable(n3, :x)
y2 = Plasmo.add_variable(n3, :y)
z2 = Plasmo.add_variable(n4, :z)

# Add subgraphs to `rg` using two different methods
Plasmo.add_subgraph(rg, rg2)
rg3 = Plasmo.add_subgraph(rg, worker = 2)

n5 = add_node(rg3, :n5)
x3 = Plasmo.add_variable(n5, :x)

@linkconstraint(rg, x + x2 + rg3[:n5][:x]  == 0);

# TODO: Need to define the objective on remotes
# TODO: Need to fix macros so that @variable, @constraint, @optinode, and @objective work; 
# TODO: Need to figure out a way to port a function to a separate worker to add to an optigraph

using JuMP
using MPI
using Ipopt


manager = MPI.MPIManager(np = 2)
addprocs(manager)

@everywhere using ParallelDataTransfer

@everywhere  using Plasmo
@everywhere  include("../../../src/ModelGraph/solver_interfaces/PipsNlpSolver.jl")
@everywhere using PipsNlpSolver
@everywhere include("../../../src/ModelGraph/solver_interfaces/plasmoPipsNlpInterface2.jl")
@everywhere using PlasmoPipsNlpInterface2
@everywhere using JuMP
# using Plasmo
# include("../../../src/ModelGraph/solver_interfaces/plasmoPipsNlpInterface2.jl")
# using PlasmoPipsNlpInterface2

#MPI.@mpi_do manager begin
function get_electricity_model(demand)
    m = Model()
    #amount of electricity produced
    @variable(m, 0<=prod<=10, start=5)
    #amount of electricity purchased or sold
    @variable(m, input)
    #amount of gas purchased
    @variable(m, gas_purchased)
    @constraint(m, gas_purchased >= prod)
    @constraint(m, prod + input == demand)
    return m
end

#Setup processor information
Ns = 8
demand = rand(Ns)*10
graph = ModelGraph()

#Create the master model
master = Model()
@variable(master,0<=gas_purchased<=8)
@objective(master,Min,gas_purchased)

#Add the master model to the graph
master_node = add_node!(graph,master)

scenm=Array{JuMP.Model}(Ns)
scen_nodes = Array{ModelNode}(Ns)
#split scenarios between processors
for j in 1:Ns
    scenm[j] = get_electricity_model(demand[j])
    node = add_node(graph,scenm[j])
    scen_nodes[j] = node
    #connect children and parent variables
    @linkconstraint(graph, master[:gas_purchased] == scenm[j][:gas_purchased])
    #reconstruct second stage objective
    @objective(scenm[j],Min,1/Ns*(scenm[j][:prod] + 3*scenm[j][:input]))
end
#create a link constraint between the subproblems (PIPS-NLP supports this kind of constraint)
@linkconstraint(graph, (1/Ns)*sum(scenm[s][:prod] for s in 1:Ns) == 8)


println("Solving with PIPS-NLP")
#
@passobj 1 workers() graph
# @passobj 1 workers() master_node
# @passobj 1 workers() scen_nodes

#@mpi_do manager pipsnlp_solve(graph,master_node,scen_nodes)
@mpi_do manager pipsnlp_solve(graph,1,collect(2:9))
rank_zero = manager.mpi2j[0]

g = @getfrom rank_zero graph
n1 = getnode(g,1)
println(getvalue(n1[:gas_purchased]))
#pipsnlp_solve(graph,master_node,scen_nodes)

#
#
# @show getobjectivevalue(graph)


#     graph.solver = IpoptSolver()
#     println()
#     println("Solving with Ipopt")
#     solve(graph)
# end

#MPI.Finalize()

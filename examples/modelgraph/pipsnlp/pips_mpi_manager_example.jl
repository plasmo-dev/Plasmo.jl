using JuMP
#using Plasmo
using MPI
using Ipopt


manager = MPI.MPIManager(np = 4)
addprocs(manager)
@mpi_do manager begin
     using Plasmo
     include("../../../src/ModelGraph/solver_interfaces/PipsNlpSolver.jl")
     include("../../../src/ModelGraph/solver_interfaces/plasmoPipsNlpInterface2.jl")
     using PipsNlpSolver
     using PlasmoPipsNlpInterface2
     using JuMP
 end
using Plasmo
include("../../../src/ModelGraph/solver_interfaces/plasmoPipsNlpInterface2.jl")
using PlasmoPipsNlpInterface2

MPI.@mpi_do manager begin
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


pipsnlp_solve(graph,master_node,scen_nodes)
end
#
#
# @show getobjectivevalue(graph)


#     graph.solver = IpoptSolver()
#     println()
#     println("Solving with Ipopt")
#     solve(graph)
# end

#MPI.Finalize()

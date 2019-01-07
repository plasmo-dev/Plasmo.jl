using JuMP
using Plasmo
using MPI
using Ipopt
using PlasmoSolverInterface

MPI.Init()

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
comm = MPI.COMM_WORLD
ncores = MPI.Comm_size(comm)
rank = MPI.Comm_rank(comm)
SPP = round(Int, floor(Ns/ncores))

graph = ModelGraph()

#Create the master model
master = Model()
@variable(master,0<=gas_purchased<=8)
@objective(master,Min,gas_purchased)

#Add the master model to the graph
master_node = add_node!(graph,master)

scenm=Array{JuMP.Model}(Ns)
scen_nodes = Array{ModelNode}(Ns)
owned = []
s = 1
#split scenarios between processors
for j in 1:Ns
    if round(Int, floor((s-1)/SPP)) == rank
        push!(owned, s)
        #get scenario model and append to parent node
        scenm[j] = get_electricity_model(demand[j])
        node = add_node(graph,scenm[j])
        scen_nodes[j] = node
        #connect children and parent variables
        @linkconstraint(graph, master[:gas_purchased] == scenm[j][:gas_purchased])
        #reconstruct second stage objective
        @objective(scenm[j],Min,1/Ns*(scenm[j][:prod] + 3*scenm[j][:input]))
    else #
        scenm[j] = Model()
        node = add_node(graph, scenm[j])
        scen_nodes[j] = node
    end
    s = s + 1
end
#create a link constraint between the subproblems (PIPS-NLP supports this kind of constraint)
@linkconstraint(graph, (1/Ns)*sum(scenm[s][:prod] for s in owned) == 8)

if rank == 0
    println("Solving with PIPS-NLP")
end
pipsnlp_solve(graph,master_node,scen_nodes)

if rank == 0
    @show getobjectivevalue(graph)
end


MPI.Finalize()

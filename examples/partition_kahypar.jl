using Plasmo
using Ipopt
using KaHyPar

modelgraph = ModelGraph()

#Add nodes to a ModelGraph
@node(modelgraph,nodes[1:4])


#Set a model on node 1
@variable(nodes[1],0 <= x <= 2)
@variable(nodes[1],0 <= y <= 3)
@constraint(nodes[1],x+y <= 4)
@objective(nodes[1],Min,x)

#Set a model on node 2
@variable(nodes[2],x >= 1)
@variable(nodes[2],0 <= y <= 5)
@NLnodeconstraint(nodes[2],exp(x)+y <= 7)
@objective(nodes[2],Min,x)

#node 3
@variable(nodes[3],x >= 0)

#node 4
@variable(nodes[4],0 <= x <= 1)


ipopt = Ipopt.Optimizer

#Link constraints take the same expressions as the JuMP @constraint macro
@linkconstraint(modelgraph,nodes[1][:x] == nodes[2][:x])
@linkconstraint(modelgraph,nodes[2][:y] == nodes[3][:x])
@linkconstraint(modelgraph,nodes[3][:x] == nodes[4][:x])

optimize!(modelgraph,ipopt)


hypergraph,hyper_map = gethypergraph(modelgraph) #create hypergraph object based on modelgraph
partition_vector = KaHyPar.partition(hypergraph,2;configuration = :edge_cut)
partition = Partition(hypergraph,partition_vector,hyper_map)
make_subgraphs!(modelgraph,partition)
new_modelgraph,ref_map = combine(modelgraph,0)

optimize!(new_modelgraph,ipopt)

#Check results
println()
println("Combined ModelGraph Solution")
println("n1[:x]= ",nodevalue(nodes[1][:x]))
println("n1[:y]= ",nodevalue(nodes[1][:y]))

println("n2[:x]= ",nodevalue(nodes[2][:x]))
println("n2[:y]= ",nodevalue(nodes[2][:y]))

println("n3[:x]= ",nodevalue(nodes[3][:x]))
println("n4[:x]= ",nodevalue(nodes[4][:x]))

println()
println("Combined Partitioned Graph Solution (solution should be the same)")
println("")
println("n1[:x]= ",nodevalue(ref_map[nodes[1][:x]]))
println("n1[:y]= ",nodevalue(ref_map[nodes[1][:y]]))

println("n2[:x]= ",nodevalue(ref_map[nodes[2][:x]]))
println("n2[:y]= ",nodevalue(ref_map[nodes[2][:y]]))

println("n3[:x]= ",nodevalue(ref_map[nodes[3][:x]]))
println("n4[:x]= ",nodevalue(ref_map[nodes[4][:x]]))

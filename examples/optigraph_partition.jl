using Plasmo
using Ipopt
using KaHyPar

function create_optigraph()
    optigraph = OptiGraph()
    @optinode(optigraph,nodes[1:4])

    #node 1
    @variable(nodes[1],0 <= x <= 2)
    @variable(nodes[1],0 <= y <= 3)
    @constraint(nodes[1],x+y <= 4)
    @objective(nodes[1],Min,x)

    #node 2
    @variable(nodes[2],x >= 1)
    @variable(nodes[2],0 <= y <= 5)
    @NLconstraint(nodes[2],exp(x)+y <= 7)
    @objective(nodes[2],Min,x)

    #node 3
    @variable(nodes[3],x >= 0)
    @variable(nodes[3],y >= 0)
    @constraint(nodes[3],x + y == 2)
    @objective(nodes[3],Max,x)

    #node 4
    @variable(nodes[4],0 <= x <= 1)
    @variable(nodes[4],y >= 0)
    @constraint(nodes[4],x + y <= 3)
    @objective(nodes[4],Max,y)

    #Link constraints take the same expressions as the JuMP @constraint macro
    @linkconstraint(optigraph,nodes[1][:x] == nodes[2][:x])
    @linkconstraint(optigraph,nodes[2][:y] == nodes[3][:x])
    @linkconstraint(optigraph,nodes[3][:x] == nodes[4][:x])

    return optigraph
end

optigraph = create_optigraph()
set_optimizer(optigraph,Ipopt.Optimizer)
optimize!(optigraph)

#Partition with KaHyPar
hypergraph,hyper_map = gethypergraph(optigraph)
partition_vector = KaHyPar.partition(hypergraph,2;configuration = :edge_cut)
partition = Partition(hypergraph,partition_vector,hyper_map)
make_subgraphs!(optigraph,partition)
set_optimizer(optigraph,Ipopt.Optimizer)
optimize!(optigraph)

#Partiton manually
optigraph = create_optigraph()
nodes = all_nodes(optigraph)
node_vectors = [[nodes[1],nodes[2]],[nodes[3],nodes[4]]]
partition = Partition(optigraph,node_vectors)
make_subgraphs!(optigraph,partition)
set_optimizer(optigraph,Ipopt.Optimizer)
optimize!(optigraph)

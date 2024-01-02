using Plasmo
graph = OptiGraph()

n1 = Plasmo.add_node(graph)
@variable(n1, x >= 0)
@variable(n1, y >= 0)
@constraint(n1, ref1, x+y==2)
print(n1[:x])

n2 = Plasmo.add_node(graph)
@variable(n2, x >= 1)
@variable(n2, y >= 2)
@constraint(n2, ref2, x+y==4)

# edge1 = Plasmo.add_edge(graph, n1, n2)
# @constraint(edge1)

@linkconstraint(graph, n1[:x] + n2[:x] == 2)



# m = Model()
# @variable(m, x[1:100000])
# Base.summarysize(m) # 11053087


# using Plasmo
# graph = OptiGraph()
# for i = 1:100000
# 	node = Plasmo.add_node(graph)
# 	@variable(node, x)
# end

#s = Base.summarysize(graph)
# centralized dict: 29607545

# dict on each node: 73543193



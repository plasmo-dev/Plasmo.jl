using Plasmo
graph = OptiGraph()
n1 = Plasmo.add_node(graph)
@variable(n1, x)
@variable(n1, y)
@constraint(n1, ref, x+y==2)

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



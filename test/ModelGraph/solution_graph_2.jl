using Plasmo


sgraph = SolutionGraph()

n1 = add_node!(sgraph)
n2 = add_node!(sgraph)

add_edge!(sgraph,n1,n2)

true

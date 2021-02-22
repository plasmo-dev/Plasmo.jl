using Plasmo
using Plots
pyplot()

graph = OptiGraph()

n1 = @optinode(graph)
@variable(n1, y >= 2)
@variable(n1,x >= 0)
@constraint(n1,x + y >= 3)
@objective(n1, Min, y)

n2 = @optinode(graph)
@variable(n2, y)
@variable(n2,x >= 0)
@constraint(n2,x + y >= 3)
@objective(n2, Min, y)

n3 = @optinode(graph)
@variable(n3, y )
@variable(n3,x >= 0)
@constraint(n3,x + y >= 3)
@objective(n3, Min, y)

#Create a link constraint linking the 3 models
@linkconstraint(graph2, n1[:y] + n2[:y] + n3[:y] == 5)

plt_graph = Plots.plot(graph2,node_labels = true, subgraph_colors = true,
layout_options = Dict(:tol => 0.01,:C => 1, :K => 1, :iterations => 100),
line_options = Dict(:linewidth => 3,:linecolor => :blue,:linealpha => 0.3),
plt_options = Dict(:markersize => 40,:markercolor => :grey,:legend => false,
:framestyle => :box,:grid => false, :size => (800,800),:axis => nothing),
annotate_options = Dict(:markersize => 20,:markercolor => :black));

plt_matrix = Plots.spy(graph2,node_labels = true);

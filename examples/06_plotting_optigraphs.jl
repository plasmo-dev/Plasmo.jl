using Plasmo
using Plots;
pyplot()
using PlasmoPlots

graph = OptiGraph()

# add nodes

n1 = @optinode(graph)
@variable(n1, y >= 2)
@variable(n1, x >= 0)
@constraint(n1, x + y >= 3)

n2 = @optinode(graph)
@variable(n2, y)
@variable(n2, x >= 0)
@constraint(n2, x + y >= 3)

n3 = @optinode(graph)
@variable(n3, y)
@variable(n3, x >= 0)
@constraint(n3, x + y >= 3)

# create a link constraint linking the 3 models
@linkconstraint(graph2, n1[:y] + n2[:y] + n3[:y] == 5)

# generate node-link plot
plt_graph = Plots.plot(
    graph2;
    node_labels=true,
    subgraph_colors=true,
    layout_options=Dict(:tol => 0.01, :C => 1, :K => 1, :iterations => 100),
    line_options=Dict(:linewidth => 3, :linecolor => :blue, :linealpha => 0.3),
    plt_options=Dict(
        :markersize => 40,
        :markercolor => :grey,
        :legend => false,
        :framestyle => :box,
        :grid => false,
        :size => (800, 800),
        :axis => nothing,
    ),
    annotate_options=Dict(:markersize => 20, :markercolor => :black),
);

# generate block layout
plt_matrix = PlasmoPlots.matrix_layout(graph2; node_labels=true);

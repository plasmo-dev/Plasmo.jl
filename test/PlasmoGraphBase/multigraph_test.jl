using Plasmo
using LightGraphs

multi = MultiGraph()

add_vertex!(multi)

add_vertex!(multi)

@assert nv(multi) == 2

add_edge!(multi,1,2)

add_edge!(multi,1,2)

@assert ne(multi) == 2

add_edge!(multi,2,1)

@assert ne(multi) == 3

true

using Plasmo
using LightGraphs

hyper = HyperGraph()

add_vertex!(hyper)

add_vertex!(hyper)

@assert nv(hyper) == 2

add_edge!(hyper,1,2)

@assert ne(hyper) == 1

add_vertex!(hyper)

add_edge!(hyper,1,2,3)

add_edge!(hyper,1,2,3)

true

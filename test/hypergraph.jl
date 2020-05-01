using Plasmo
using LightGraphs
using Test

hyper = HyperGraph()
add_node!(hyper)
add_node!(hyper)
add_node!(hyper)
add_node!(hyper)
add_node!(hyper)
add_node!(hyper)

add_hyperedge!(hyper,1,2,3)
add_hyperedge!(hyper,1,2)
add_hyperedge!(hyper,4,1,3)

@test hyper.hyperedge_map[1] == HyperEdge(1,2,3)
@test hyper.hyperedge_map[2] == HyperEdge(1,2)
@test hyper.hyperedge_map[3] == HyperEdge(1,3,4)

@test Set([1,2,3]) == hyper.hyperedge_map[1].vertices
@test Set([1,2]) == hyper.hyperedge_map[2].vertices
@test Set([1,3,4]) == hyper.hyperedge_map[3].vertices

@test length(hyper.vertices) == 6
@test length(hyper.hyperedge_map) == 3

#4 vertices are connected by 3 hyperedges
A = incidence_matrix(hyper)
@test size(A) == (4,3)


#Project to standard graph
clique_graph,projection_map = clique_expansion(hyper)
@test nv(clique_graph) == 6
@test ne(clique_graph) == 5


true

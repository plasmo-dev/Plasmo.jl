#println("Testing Interface Graph Functions")

import Plasmo.PlasmoGraphBase:create_node,create_edge
using Plasmo.PlasmoGraphBase
using LightGraphs

#This is an example of creating graphs that inherit all of the base graph functionality
struct TestGraph <: AbstractPlasmoGraph
    basegraph::BasePlasmoGraph
    field1::Float64
    field2::Float64
end
TestGraph() = TestGraph(BasePlasmoGraph(DiGraph),1,2)

struct TestNode <: AbstractPlasmoNode
    basenode::BasePlasmoNode
    node_field1::Float64
    node_field2::Integer
end
TestNode() = TestNode(BasePlasmoNode(),1,2)
create_node(graph::TestGraph) = TestNode()

struct TestEdge <: AbstractPlasmoEdge
    baseedge::BasePlasmoEdge
    edge_field::Float64
end
TestEdge() = TestEdge(BasePlasmoEdge(),100)
create_edge(graph::TestGraph) = TestEdge()
#Test PlasmoGraph constructor
graph = TestGraph()
n1 = add_node!(graph)
n2 = add_node!(graph)
n3 = add_node!(graph)

e1 = add_edge!(graph,1,2)
e2 = add_edge!(graph,3,2)

true

#TODO Write a multigraph implementation for Workflows
struct MultiEdge <: LightGraphs.AbstractEdge
    src::Int
    dst::Int
    n_edges::UInt  #each individual edge in a multi-edge between nodes
end
MultiEdge(p::Pair) = MultiEdge(p.first,p.second,1)
MultiEdge(p::Pair,n_edges::UInt) = MultiEdge(p.first,p.second,n_edges)

import Metis

function Metis.partition(graph::ModelGraph,n_parts::Int64;alg = :KWAY)
    ugraph = getunipartitegraph(graph)
    lg = getlightgraph(ugraph)
    #TODO Make metis account for weights
    parts = Metis.partition(lg,n_parts,alg = alg)
    unique_parts = unique(parts)
    nparts = length(unique_parts)

    partitions = Dict{Int64,Vector{Int64}}((k,[]) for k in unique_parts)
    for modelnode in getnodes(graph)
        index = getindex(graph,modelnode)
        part = parts[index]
        push!(partitions[part],index)
    end
    return partitions
end

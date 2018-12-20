import Metis
import LightGraphs

function partition(graph::ModelGraph,n_parts::Int64;alg = :KWAY)
    ugraph = getunipartitegraph(graph)
    lg = getlightgraph(ugraph)
    #TODO Make metis account for weights
    parts = Metis.partition(lg,n_parts,alg = alg)
    unique_parts = unique(parts)
    nparts = length(unique_parts)

    partition_dict = Dict{Int64,Vector{Int64}}((k,[]) for k in unique_parts)
    for modelnode in getnodes(graph)
        index = getindex(graph,modelnode)
        part = parts[index]
        push!(partition_dict[part],index)
    end

    partitions = collect(values(partition_dict))

    return partitions
end

function LightGraphs.label_propagation(graph::ModelGraph)
    ugraph = getunipartitegraph(graph)
    lg = getlightgraph(ugraph)

    parts = LightGraphs.label_propagation(lg)[1]
    unique_parts = unique(parts)
    nparts = length(unique_parts)

    partition_dict = Dict{Int64,Vector{Int64}}((k,[]) for k in unique_parts)
    for modelnode in getnodes(graph)
        index = getindex(graph,modelnode)
        part = parts[index]
        push!(partition_dict[part],index)
    end

    partitions = collect(values(partition_dict))

    return partitions
end

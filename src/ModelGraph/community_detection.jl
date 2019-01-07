import LightGraphs

"""
LightGraphs.label_propagation(graph::ModelGraph)

Return partitions corresponding to detected communities using the LightGraphs label propagation algorithm.
"""
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

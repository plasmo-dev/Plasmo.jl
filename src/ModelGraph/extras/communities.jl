import CommunityDetection

"""
LightGraphs.label_propagation(graph::ModelGraph)

Return partitions corresponding to detected communities using the LightGraphs label propagation algorithm.
"""
function CommunityDetection.community_detection_nback(graph::ModelGraph,args...;kwargs...)
    ugraph = getunipartitegraph(graph)
    lg = getlightgraph(ugraph)

    parts = CommunityDetection.community_detection_nback(lg,args...;kwargs...)
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

function CommunityDetection.community_detection_bethe(graph::ModelGraph,args...;kwargs...)
    ugraph = getunipartitegraph(graph)
    lg = getlightgraph(ugraph)

    parts = CommunityDetection.community_detection_bethe(lg,args...;kwargs...)
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

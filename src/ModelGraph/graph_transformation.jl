#Functions  that do graph transformations to facilitate different decomposition algorithms
function getmodeltree(graph::ModelGraph;root_node = nothing)
    #1.) If no root_node, lift all the link constraints into a root node
    #if root_node == nothing


    #2.) If there is a root node, create the tree by recursively going out
    #3.) Lift hyper-constraints into root node
end

function getunipartitegraph(graph::ModelGraph)
end

function getbipartitegraph(graph::ModelGraph)
    #convert hypergraph to a bipartite graph to do partitioning and community detection
end

function getequationgraph(graph::ModelGraph)
end

function getequationgraph(model::JuMP.Model)
end

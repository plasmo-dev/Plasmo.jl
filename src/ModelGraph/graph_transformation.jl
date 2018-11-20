#Functions  that do graph transformations to facilitate different decomposition algorithms
function ModelTree(graph::ModelGraph;root_node = nothing)
    #1.) If no root_node, lift all the link constraints into a root node
    #2.) If there is a root node, create the tree by recursively going out
    #3.) Lift hyper-constraints into root node
end

function getunipartitegraph(graph::ModelGraph)
end

function getbipartitegraph(graph::ModelGraph)
end

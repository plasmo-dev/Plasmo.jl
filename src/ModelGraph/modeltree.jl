mutable struct ModelTree <: AbstractModelGraph
    basegraph::BasePlasmoGraph                   #Model graph structure.  Put constraint references on edges
    linkmodel::LinkModel                         #Using composition to represent a graph as a "Model".  Someday I will figure out how to do multiple inheritance.
    serial_model::Nullable{AbstractModel}        #The internal serial model for the graph.  Returned if requested by the solve
end
ModelTree() = ModelTree(BasePlasmoGraph(DiGraph),LinkModel(),Nullable())

function setroot(tree::ModelTree)
end

function addchild!(tree::ModelTree,node::ModelNode)
end

#A ModelTree is a specific graph structure containing a root node and a series of levels that can contain nodes with models.
#Linkconstraints can be made between nodes on adjacent levels.  Each node can only have one parent.

mutable struct ModelTree <: AbstractModelGraph
    basegraph::BasePlasmoGraph                   #Model graph structure.  Put constraint references on edges
    linkmodel::LinkModel                         #Using composition to represent a graph as a "Model".  Someday I will figure out how to do multiple inheritance.
    serial_model::Union{AbstractModel,Nothing}        #The internal serial model for the tree.  Returned if requested by the solve
    levels::Vector{Vector{ModelNode}}            #the number of levels (or stages) in the tree
    levelmap::Dict{ModelNode,Int}                #levelmap:  Each node maps to a level in the tree child map for each node index.  Helpful for quickly getting child nodes
end
ModelTree(;solver = JuMP.UnsetSolver()) = ModelTree(BasePlasmoGraph(LightGraphs.DiGraph),LinkModel(;solver = solver),nothing,Vector{Vector{ModelNode}}(),Dict{ModelNode,Int}())

create_node(tree::ModelTree) = ModelNode()
create_edge(tree::ModelTree) = LinkingEdge()

#Setting root should change edge directions
#setroot(tree::ModelTree,id::Int) = tree.root_node = getnode(tree,id)
function setroot(tree::ModelTree,node::ModelNode)
    #tree.root = node
    if  length(tree.levels) == 0
        add_level!(tree)
    end
    tree.levels[1] = [node]
    tree.levelmap[node] = 1
    #NOTE: We should re-create the tree if this gets called
end

getroot(tree::ModelTree) = tree.levels[1][1]

function add_level!(tree::ModelTree)
    push!(tree.levels,ModelNode[])
end


function add_node!(tree::ModelTree;level = nothing)
    #Extend from base method

    if level == nothing

        basegraph = getbasegraph(tree)
        LightGraphs.add_vertex!(basegraph.lightgraph)
        index = LightGraphs.nv(basegraph.lightgraph)
        label = Symbol("node"*string(index))

        node = create_node(tree)                   #create a node for the given graph type
        basenode = getbasenode(node)
        basenode.indices[basegraph] = index             #Set the index of this node in this basegraph
        add_node!(basegraph.nodedict,node,index)

        #New stuff
        #Add node to a tree structure by default
        if  length(tree.levels) == 0 #tree.root == nothing        #make the node the root
            setroot(tree,node)
            #tree.levelmap[node] = 1
        elseif length(tree.levels) == 1 #add node to the second level
            add_level!(tree)
            push!(tree.levels[2],node)
            tree.levelmap[node] = 2
        else
            push!(tree.levels[2],node)
            tree.levelmap[node] = 2
        end
        return node

    else
        node = add_node!(tree,level)
        return node
    end
end

function add_node!(tree::ModelTree,level::Int)
    level > 0 || throw(error("Tree level must be greater than zero"))
    level > length(tree.levels) + 1 && throw(error("Tree does not contain levels yet.  You may need to add a parent level first"))

    basegraph = getbasegraph(tree)
    LightGraphs.add_vertex!(basegraph.lightgraph)
    index = LightGraphs.nv(basegraph.lightgraph)
    label = Symbol("node"*string(index))

    node = create_node(tree)                   #create a node for the given graph type
    basenode = getbasenode(node)
    basenode.indices[basegraph] = index             #Set the index of this node in this basegraph
    add_node!(basegraph.nodedict,node,index)

    if level == 1
        setroot(tree,node)
        return node
    end

    if level > length(tree.levels)
        add_level!(tree)
    end

    push!(tree.levels[level],node)
    tree.levelmap[node] = level
    return node
end

function add_node!(tree::ModelTree,m::AbstractModel,level::Int)
    node = add_node!(tree,level)
    setmodel!(node,m)
    return node
end

#TODO
function getchildren(tree::ModelTree,node::ModelNode)
    #neighbors_out
    #Look at node link constraints OR look at childmap
end
function getparent(tree::ModelTree,node::ModelNode)
    #neighbors_in
end

getlevel(tree::ModelTree,node::ModelNode) = tree.levelamp[node]
getnumlevels(tree::ModelTree) = length(tree.levels)

#Store link constraint in the given graph.  Store a reference to the linking constraint on the nodes which it links
#ModelTree enforces a linkconstraint structure
function addlinkconstraint(tree::ModelTree,con::AbstractConstraint)
    isa(con,JuMP.LinearConstraint) || throw(error("Link constraints must be linear.  If you're trying to add quadtratic or nonlinear links, try creating duplicate variables and linking those"))
    vars = con.terms.vars
    nodes = unique([getnode(var) for var in vars])  #each var belongs to a node
    length(nodes) == 2 || error("Linking constraints on ModelTree must be between 2 nodes")
    tree.levelmap[nodes[1]] != tree.levelmap[nodes[2]] || throw(error("Linking constraints on ModelTree must connect different levels"))
    abs(tree.levelmap[nodes[1]] - tree.levelmap[nodes[2]]) == 1 || throw(error("Linking constraints on ModelTree must connect adjacent levels"))
    #Check if node2 already has a parent

    ref = JuMP.addconstraint(tree.linkmodel,con)
    link_edge = add_edge!(tree,ref)  #adds edge and a contraint reference to all objects involved in the constraint
    return link_edge
end

#Add directed edge to graph using linkconstraint reference
function add_edge!(tree::ModelTree,ref::JuMP.ConstraintRef)

    con = LinkConstraint(ref)   #Get the Linkconstraint object so we can inspect the nodes on it
    vars = con.terms.vars
    nodes = unique([getnode(var) for var in vars])  #each var belongs to a node
    #check node levels

    if !(has_edge(tree,getindex(tree,nodes[1]),getindex(tree,nodes[2])))
        edge = add_edge!(tree,nodes[1],nodes[2])  #constraint edge connected to more than 2 nodes
    else
        edge = getedge(tree,getindex(tree,nodes[1]),getindex(tree,nodes[2]))
    end

    push!(edge.linkconrefs,ref)
    for node in nodes
        if !haskey(node.linkconrefs,tree)
            node.linkconrefs[tree] = [ref]
        else
            push!(node.linkconrefs[tree],ref)
        end
    end
    return edge
end

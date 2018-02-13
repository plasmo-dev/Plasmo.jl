# using Plasmo
# using JuMP
# using LightGraphs
# import Plasmo:getsolution,AbstractGraph,AbstractNode,AbstractEdge,_copy_subgraphs!,add_node!
# import LightGraphs:add_edge!
#A lot of this might become obsolete if JuMP solution containers become a thing
mutable struct SolutionData
    variable_values::Dict{Symbol,Any}
    objVal::Number
end
SolutionData() = SolutionData(Dict{Symbol,Any}(),NaN)

mutable struct SolutionGraph <: AbstractPlasmoGraph
    graph::AbstractGraph                        #The underlying lightgraph
    label::Symbol
    index::Integer                              #The index of this graph within a higher level graph (i.e. its index in another graph's subgraphlist) 0 means it isn't a subgraph
    subgraphlist::Vector{AbstractPlasmoGraph}   #How plasmo manages structure
    attributes::Dict{Any,Any}                   #e.g. LinkData; might make primary attributes (like models) into actual fields
    nodes::Dict{Int,AbstractNode}               #Includes nodes in the subgraphs as well
    edges::Dict{LightGraphs.Edge,AbstractEdge}  #Includes edges in the subgraphs as well
    objVal::Number
end
SolutionGraph() = SolutionGraph(DiGraph(),gensym(),0,AbstractGraph[],Dict(),Dict{Int,AbstractNode}(),Dict{LightGraphs.Edge,AbstractEdge}(),NaN)

mutable struct SolutionNode <: AbstractNode
    index::Dict{AbstractPlasmoGraph,Int} #map to an index in each graph containing the node
    label::Symbol
    attributes::Dict{Any,Any}  #A model is an attribute
    solution_data::SolutionData
end

SolutionNode() = SolutionNode(Dict{SolutionGraph,Int}(), Symbol("node"),Dict{Any,Any}(),SolutionData())
function SolutionNode(g::SolutionGraph)
    add_vertex!(g.graph)
    i = nv(g.graph)
    label = Symbol("node"*string(i))
    node = SolutionNode(Dict(g => i),label,Dict(),SolutionData())
    g.nodes[i] = node
    return node
end

#Add an existing node to a graph.  It's possible to pass a user specified index.  This is useful for copying graphs
create_solution_node() = SolutionNode()
add_node!(g::SolutionGraph) = SolutionNode(g)

#This will be a network thing eventually...
mutable struct SolutionEdge <: AbstractEdge
    index::Dict{AbstractPlasmoGraph,LightGraphs.Edge}
    label::Symbol
    attributes::Dict{Any,Any}
    solution_data::SolutionData
end


#Edge constructors
SolutionEdge() = SolutionEdge(Dict{SolutionGraph,LightGraphs.Edge}(), Symbol("edge"),Dict{Any,Any}(),SolutionData())
function SolutionEdge(g::AbstractPlasmoGraph,edge::LightGraphs.Edge)
    add_edge!(g.graph,edge)
    label = Symbol("edge"*string(edge))
    pedge = SolutionEdge(Dict(g => edge),label,Dict(),SolutionData())
    g.edges[edge] = pedge
    return pedge
end

add_edge!(g::SolutionGraph,edge::LightGraphs.Edge) = SolutionEdge(g,edge)
add_edge!(g::SolutionGraph,src::Int,dst::Int) = SolutionEdge(g,LightGraphs.Edge(src,dst))
add_edge!(g::SolutionGraph,src::AbstractNode,dst::AbstractNode) = SolutionEdge(g,LightGraphs.Edge(src.index[g],dst.index[g]))

#copy solution data out of plasmo node or edge
function setsolutiondata(ne::NodeOrEdge,snode::Union{SolutionNode,SolutionEdge})
    for (key,var) in getnodevariables(ne)   #This is grabbing constraint references too....
        if isa(var,Array) || isa(var,Dict)# || isa(var,JuMP.Variable)
            vals = JuMP.getvalue(var)  #get value of the
            snode.solution_data.variable_values[key] = vals
        elseif isa(var,JuMP.JuMPArray)
            vals = JuMP.getvalue(var).innerArray  #get value of the
            snode.solution_data.variable_values[key] = vals
        elseif isa(var,JuMP.JuMPDict)
            vals = JuMP.getvalue(var).innerArray  #get value of the
            snode.solution_data.variable_values[key] = vals
        elseif isa(var,JuMP.Variable)
            val = JuMP.getvalue(var)
            snode.solution_data.variable_values[key] = val
        else
            error("encountered a variable type not recognized")
        end
    end
end

function copy_attributes(ne::NodeOrEdge,snode::Union{SolutionNode,SolutionEdge})
    merge!(snode.attributes,ne.attributes)
end

function copy_attributes(graph::AbstractPlasmoGraph,sgraph::SolutionGraph)
    merge!(sgraph.attributes,graph.attributes)
end

#getindex(snode::Union{SolutionNode,SolutionEdge},s::Symbol) = getmodel(nodeoredge)[s]

function getvalue(snode::Union{SolutionNode,SolutionEdge},s::Symbol)
    return snode.solution_data.variable_values[s]
end


function getsolution(graph::PlasmoGraph)
    solution_graph = SolutionGraph()
    _copy_subgraphs!(graph,solution_graph)
    #first copy all nodes, then setup all the subgraphs
    for (index,node) in getnodes(graph)
        new_node = create_solution_node()
        add_node!(solution_graph,new_node,index = index)  #create the node and add a vertex to the top level graph.  We pass the index explicity for this graph
        node_index = getindex(node) #returns dict of {graph => index}
        for igraph in keys(node_index)       #For each subgraph this node is contained in....
            if igraph.index != 0             #if it's not the top level graph
                graph_index = igraph.index   #the index of this subgraph
                subgraph = solution_graph.subgraphlist[graph_index]  #the flat_model subgraph
                add_node!(subgraph,new_node,index = node.index[igraph])
            end
        end
    end
    for (index,edge) in getedges(graph)
        pair = getindex(graph,edge)
        new_nodes = getsupportingnodes(solution_graph,pair)
        new_edge = add_edge!(solution_graph,new_nodes[1],new_nodes[2])
        #new_edge.index[flat_graph] = index
        for igraph in keys(edge.index)
            if igraph.index != 0
                index = igraph.index
                subgraph = solution_graph.subgraphlist[index]
                pair = getindex(igraph.subgraphlist[index],new_edge)
                add_edge!(subgraph,pair)
            end
        end
    end

    #Get variable values
    for (index,nodeoredge) in getnodesandedges(graph)
        solution_nodeoredge = getnodeoredge(solution_graph,index)       #get the corresponding node or edge in graph2
        #nodeoredge2.attributes[:Solution] = SolutionData()
        setsolutiondata(nodeoredge,solution_nodeoredge)
        copy_attributes(nodeoredge,solution_nodeoredge)
        copy_attributes(graph,solution_graph)
        #nodeoredge2.attributes[:Solution].objVal = getobjectivevalue(nodeoredge)
    end
    return solution_graph
end

#use a solution graph to initialize a plasmo model graph
#Works as long as graph and solution_graph have the exact same structure
function setsolution(graph::PlasmoGraph,solution_graph::SolutionGraph,)
    for (index,nodeoredge) in getnodesandedges(graph)
        solution_nodeoredge = getnodeoredge(solution_graph,index)       #get the corresponding node or edge in the solution graph
        #now set the graph to its solution
        nmodel = getmodel(nodeoredge)
        for (key,var) in getnodevariables(nodeoredge)
            vals = solution_nodeoredge.solution_data.variable_values[key]
            if isa(var,Array) || isa(var,JuMP.JuMPArray)# || isa(var,JuMP.Variable)
                Plasmo.setarrayvalue(var,vals)
            elseif isa(var,Dict) || isa(var,JuMP.JuMPDict)
                Plasmo.setvalue(var,vals)
            elseif isa(var,JuMP.Variable)
                JuMP.setvalue(var,vals)
            else
                error("encountered a variable type not recognized")
            end
        end
    end
end

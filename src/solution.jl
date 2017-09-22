#A lot of this might become obsolete if JuMP solution containers become a thing
type SolutionData
    variable_values::Dict{Symbol,Any}
    objVal::Number
end
SolutionData() = SolutionData(Dict{Symbol,Any}(),NaN)

type SolutionGraph <: AbstractPlasmoGraph
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

# #Add nodes and edges to graph models.  These are used for model instantiation from a graph
# function add_node!(m::Model; index = nv(getgraph(m).graph)+1)
#     is_graphmodel(m) || error("Can only add nodes to graph models")
#     @assert is_graphmodel(m)
#     node = JuMPNode(Dict{AbstractPlasmoGraph,Int}(), Symbol("node"),Dict(),NodeData())
#     add_node!(getgraph(m),node,index = index)
#     return node
# end
#
# function add_edge!(m::Model,node1::JuMPNode,node2::JuMPNode)
#     is_graphmodel(m) || error("Can only add nodes to graph models")
#     @assert is_graphmodel(m)
#     edge = JuMPEdge(Dict{AbstractPlasmoGraph,Edge}(), Symbol("edge"),Dict{Any,Any}(),NodeData())
#     add_edge!(getgraph(m),edge,node1,node2)
#     return edge
# end

function getsolution(graph::PlasmoGraph)
    solution_graph = SolutionGraph()
    _copy_subgraphs!(graph,solution_graph)
    #first copy all nodes, then setup all the subgraphs
    for (index,node) in getnodes(graph)
        new_node = add_node!(solution_graph,index = index)  #create the node and add a vertex to the top level graph.  We pass the index explicity for this graph
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

    for (index,nodeoredge) in getnodesandedges(graph)
        nodeoredge2 = getnodeoredge(solution_graph,index)       #get the corresponding node or edge in graph2
        nodeoredge2.attributes[:Solution] = SolutionData()
        for (key,var) in getnodevariables(nodeoredge)
            if isa(var,Array) || isa(var,Dict)# || isa(var,JuMP.Variable)
                vals = JuMP.getvalue(var)  #get value of the
                nodeoredge2.attributes[:Solution].variable_values[key] = vals
            elseif isa(var,JuMP.JuMPArray)
                vals = JuMP.getvalue(var).innerArray  #get value of the
                nodeoredge2.attributes[:Solution].variable_values[key] = vals
            elseif isa(var,JuMP.JuMPDict)
                vals = JuMP.getvalue(var).innerArray  #get value of the
                nodeoredge2.attributes[:Solution].variable_values[key] = vals
            elseif isa(var,JuMP.Variable)
                val = JuMP.getvalue(var)
                nodeoredge2.attributes[:Solution].variable_values[key] = val
            else
                error("encountered a variable type not recognized")
            end
        end
        #nodeoredge2.attributes[:Solution].objVal = getobjectivevalue(nodeoredge)
    end
end

function setsolution(graph1::SolutionGraph,graph2::AbstractPlasmoGraph) end

# function setsolution(graph1::AbstractPlasmoGraph,graph2::AbstractPlasmoGraph)
#     for (index,nodeoredge) in getnodesandedges(graph1)
#         nodeoredge2 = getnodeoredge(graph2,index)       #get the corresponding node or edge in graph2
#         for (key,var) in getnodevariables(nodeoredge)
#             var2 = nodeoredge2[key]
#             if isa(var,JuMP.JuMPArray) || isa(var,Array)# || isa(var,JuMP.Variable)
#                 vals = JuMP.getvalue(var)  #get value of the
#                 Plasmo.setarrayvalue(var2,vals)  #the dimensions have to line up for arrays
#             elseif isa(var,JuMP.JuMPDict) || isa(var,Dict)
#                 Plasmo.setvalue(var,var2)
#             elseif isa(var,JuMP.Variable)
#                 JuMP.setvalue(var2,JuMP.getvalue(var))
#             else
#                 error("encountered a variable type not recognized")
#             end
#         end
#         #TODO Also set the node objectives
#         if hasmodel(nodeoredge2)
#             m = getmodel(nodeoredge2)
#             m.objVal = getvalue(m.obj)
#         end
#     end
# end

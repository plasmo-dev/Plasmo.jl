mutable struct SolutionGraph <: AbstractPlasmoGraph
    basegraph::BasePlasmoGraph
    linkcon_duals::Vector{Number}
    objval::Number
end
SolutionGraph() = SolutionGraph(BasePlasmoGraph(HyperGraph),Number[],0)

mutable struct SolutionNode <: AbstractModelNode
    basenode::BasePlasmoNode
    objval::Number
    variable_value_map::Dict{Symbol,Any}
    variable_values::Vector{Number}
    constraint_duals::Vector{Number}
end
create_node(graph::SolutionGraph) = SolutionNode(BasePlasmoNode(),0,Dict{Symbol,Number}(),Number[],Number[])

mutable struct SolutionEdge <: AbstractLinkingEdge
    baseedge::BasePlasmoEdge
    linkconduals::Vector{Number}
end
SolutionEdge() = SolutionEdge(BasePlasmoEdge(),Number[])
create_edge(graph::SolutionGraph) = SolutionEdge()

#copy solution data out of plasmo node or edge
function setsolutiondata(node::ModelNode,solution_node::SolutionNode)
    for (key,var) in getnodevariablemap(node)   #This is grabbing constraint references too....
        if isa(var,Array) || isa(var,Dict)# || isa(var,JuMP.Variable)
            vals = JuMP.getvalue(var)  #get value of the
            solution_node.variable_value_map[key] = vals
        elseif isa(var,JuMP.JuMPArray)
            vals = JuMP.getvalue(var).innerArray  #get value of the
            solution_node.variable_value_map[key] = vals
        elseif isa(var,JuMP.JuMPDict)
            vals = JuMP.getvalue(var).innerArray  #get value of the
            solution_node.variable_value_map[key] = vals
        elseif isa(var,JuMP.Variable)
            val = JuMP.getvalue(var)
            solution_node.variable_value_map[key] = val
        else
            error("encountered a variable type not recognized")
        end
    end
    for var in getnodevariables(node)
        val = getvalue(var)
        push!(solution_node.variable_values,val)
    end
    #TODO Get constraint duals

end

#TODO Copy attributes
# function copy_attributes(ne::NodeOrEdge,solution_node::Union{SolutionNode,SolutionEdge})
#     merge!(solution_node.attributes,ne.attributes)
# end
#
# function copy_attributes(graph::AbstractPlasmoGraph,sgraph::SolutionGraph)
#     merge!(sgraph.attributes,graph.attributes)
# end

function getvalue(solution_node::SolutionNode,s::Symbol)
    return solution_node.variable_value_map[s]
end


function getsolution(graph::ModelGraph)
    # solution_graph = SolutionGraph()
    # _copy_subgraphs!(graph,solution_graph)
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
function setsolution(graph::ModelGraph,solution_graph::SolutionGraph)
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

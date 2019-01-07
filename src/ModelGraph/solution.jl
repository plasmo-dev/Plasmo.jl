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

    for i = 1:num_var(node)
        node1_var = getnodevariable(node,i)
        val = getvalue(node1_var)
        push!(solution_node.variable_values,val)
    end

    # for var in getnodevariables(node)
    #     val = getvalue(var)
    #     push!(solution_node.variable_values,val)
    # end

    # TODO Constraint Duals
    # for con in node.constraintlist
    #     push!(solution_node.constraint_duals,getdual(con))
    # end
    solution_node.objval = getobjectivevalue(node)
end

function JuMP.getvalue(solution_node::SolutionNode,s::Symbol)
    return solution_node.variable_value_map[s]
end

#Get a solution graph from a model graph
function getsolution(model_graph::ModelGraph)
    solution_graph = copy_graph(model_graph,to_graph_type = SolutionGraph)
    #Get variable values
    for node in getnodes(model_graph)
        index = getindex(model_graph,node)
        solution_node = getnode(solution_graph,index)       #get the corresponding node or edge in graph2
        setsolutiondata(node,solution_node)
    end
    return solution_graph
end

function string(node::SolutionNode)
    "Solution Node"
end
print(io::IO,node::SolutionNode) = print(io, string(node))
show(io::IO,node::SolutionNode) = print(io,node)

#use a solution graph to initialize a plasmo model graph
#Works as long as graph and solution_graph have the exact same structure
# #TODO dual warm start solution
# function setsolution(model_graph::ModelGraph,solution_graph::SolutionGraph)  #set ModelGraph solution with SolutionGraph solution
#     for node in getnodes(model_graph)
#         index = getindex(model_graph,node)
#         solution_node = getnode(solution_graph,index)       #get the corresponding node or edge in the solution graph
#         #now set the graph to its solution
#         node_model = getmodel(node)
#         for (key,var) in getnodevariables(node)
#             vals = solution_node.variable_values[key]
#             if isa(var,Array) || isa(var,JuMP.JuMPArray)# || isa(var,JuMP.Variable)
#                 Plasmo.setarrayvalue(var,vals)
#             elseif isa(var,Dict) || isa(var,JuMP.JuMPDict)
#                 Plasmo.setvalue(var,vals)
#             elseif isa(var,JuMP.Variable)
#                 JuMP.setvalue(var,vals)
#             else
#                 error("encountered a variable type not recognized")
#             end
#         end
#     end
# end

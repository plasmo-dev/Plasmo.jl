function _find_parent_graph(vref_subgraph::OptiGraph, subgraphs::Vector{OptiGraph})
    if vref_subgraph.parent_graph in subgraphs
        return vref_subgraph.parent_graph
    elseif !(isnothing(vref_subgraph.parent_graph))
        return _find_parent_graph(vref_subgraph.parent_graph, subgraphs)
    else
        error("variable does not belong to any of the given subgraphs")
    end
end

function _get_variable_subgraph(vref::NodeVariableRef, subgraphs::Vector{OptiGraph})
    vref_subgraph = source_graph(JuMP.owner_model(vref))
    if vref_subgraph in subgraphs
        return vref_subgraph
    else
        return _find_parent_graph(vref_subgraph, subgraphs)
    end
end

function _convert_local_to_remote(con::JuMP.ScalarConstraint, variable_map::Dict{NodeVariableRef, RemoteVariableRef})
    rfunc = _convert_local_to_remote(con.func, variable_map)
    return ScalarConstraint(rfunc, con.set)
end

function _build_variable_map(graph::OptiGraph, graph_map::Dict)
    edges = local_edges(graph)
    variable_map = Dict{NodeVariableRef, RemoteVariableRef}()
    node_map = Dict{OptiNode, RemoteNodeRef}()
    subgraphs = collect(keys(graph_map))
    for e in edges
        for c in all_constraints(e)
            all_vars = extract_variables(c)
            for var in all_vars
                if !(var in keys(variable_map))
                    node = JuMP.owner_model(var)
                    variable_subgraph = _get_variable_subgraph(var, subgraphs)
                    if !(node in keys(node_map))
                        rnode = RemoteNodeRef(graph_map[variable_subgraph], node.idx, node.label)
                        node_map[node] = rnode
                    else
                        rnode = node_map[node]
                    end
                    rvar = RemoteVariableRef(rnode, var.index, Symbol(name(var)))
                    variable_map[var] = rvar
                end
            end
        end
    end
    return variable_map
end

function _convert_local_to_remote(func::GenericAffExpr{Float64, Plasmo.NodeVariableRef}, variable_map::Dict{NodeVariableRef, RemoteVariableRef})
    new_func = GenericAffExpr{Float64, Plasmo.RemoteVariableRef}(func.constant)
    for (var, val) in func.terms
        remote_var = variable_map[var]
        new_func.terms[remote_var] = val
    end
    return new_func
end

function _convert_local_to_remote(func::GenericQuadExpr{Float64, Plasmo.NodeVariableRef}, variable_map::Dict{NodeVariableRef, RemoteVariableRef})
    new_aff = _convert_local_to_remote(func.aff, variable_map)
    new_terms = OrderedDict{UnorderedPair{RemoteVariableRef}, Float64}()
    for (pair, val) in func.terms
        remote_var1 = variable_map[pair.a]
        remote_var2 = variable_map[pair.b]
        new_pair = UnorderedPair(remote_var1, remote_var2)
        new_terms[new_pair] = val
    end
    return GenericQuadExpr{Float64, Plasmo.RemoteVariableRef}(new_aff, new_terms)
end

function _convert_local_to_remote(func::GenericNonlinearExpr{Plasmo.NodeVariableRef}, variable_map::Dict{NodeVariableRef, RemoteVariableRef})
    V = Plasmo.RemoteVariableRef
    ret = JuMP.GenericNonlinearExpr{V}(func.head, Any[])
    stack = Tuple{JuMP.GenericNonlinearExpr, Any}[]

    for arg in reverse(func.args)
        push!(stack, (ret, arg))
    end
    while !isempty(stack)
        parent, arg = pop!(stack)
        if arg isa GenericNonlinearExpr
            new_ret = JuMP.GenericNonlinearExpr{V}(arg.head, Any[])
            push!(parent.args, new_ret)
            for child in reverse(arg.args)
                push!(stack, (new_ret, _convert_local_to_remote(child, variable_map)))
            end
        else
            push!(parent.args, _convert_local_to_remote(arg, variable_map))
        end
    end
    return ret
end

function _convert_local_to_remote(func::NodeVariableRef, variable_map::Dict{NodeVariableRef, RemoteVariableRef})
    return variable_map[func]
end

function _convert_local_to_remote(
    func::T, 
    variable_map::Dict{NodeVariableRef, RemoteVariableRef}
) where {T <: Union{
        RemoteVariableRef, 
        Float64, 
        GenericAffExpr{Float64, RemoteVariableRef}, 
        GenericQuadExpr{Float64, RemoteVariableRef}, 
        GenericNonlinearExpr{RemoteVariableRef}, 
        Nothing
    }}
    return func
end

function distribute_graph(graph::OptiGraph, workers::Vector{Int})
    subgraphs = local_subgraphs(graph)
    @assert length(subgraphs) == length(workers) 
    graph_map = Dict{OptiGraph, RemoteOptiGraph}()
    rgraph = RemoteOptiGraph()
    for i in 1:length(workers)
        darray = distribute([subgraphs[i]], procs=[workers[i]])
        new_rgraph = RemoteOptiGraph(
            workers[i], 
            darray, 
            nothing,
            Vector{RemoteOptiGraph}(), 
            Vector{Plasmo.RemoteOptiEdge}(), 
            Plasmo.RemoteElementData(),
            Dict{Symbol,Any}(),
            subgraphs[i].label, #not sure yet whether the remote and local should have the same name, but doing that for now
            Dict{Symbol, Any}()
        )
        add_subgraph(rgraph, new_rgraph)
        graph_map[subgraphs[i]] = new_rgraph
    end

    variable_map = _build_variable_map(graph, graph_map)
    edges = local_edges(graph)
    for edge in edges
        for con in all_constraints(edge)
            co = constraint_object(con)
            rco = _convert_local_to_remote(co, variable_map)
            JuMP.add_constraint(rgraph, rco)
            # TODO: pass names of link constraints to new graph; not trivial to do because these show up as values of the OptiGraphs object Dict
        end
    end
    return rgraph
end

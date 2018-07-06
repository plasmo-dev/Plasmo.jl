
function aggregate!(model_graph::ModelGraph,nodes::Vector{ModelNode})
    local_link_constraints = []  #all nodes in link constraint are in the set of nodes given
    cross_link_constraints = []  #at least one node in a link constraint is not in the node subset (must be connected to the rest of the graph)

    #Check each node's link constraints.  Add it to one of the above lists.
    checked_links = []
    for node in nodes
        for (graph,links) in getlinkconstraints(node)
            for link in links
                if !(link in checked_links)  #If it's a new link constraint
                    vars = link.terms.vars
                    var_nodes = map(getnode,vars)
                    if all(node -> node in nodes,var_nodes)
                        push!(local_link_constraints,link)
                    else
                        push!(cross_link_constraints,link)
                    end
                    push!(checked_links,link)
                end
            end
        end
    end

    #Build up an aggregate model with given nodes.
    aggregate_model =  JuMPGraphModel()
    jump_graph = getgraph(aggregate_model)

    #COPY NODE MODELS INTO AGGREGATE MODEL
    var_maps = Dict()
    for model_node in nodes  #for each node in the model graph
        nodeindex = getindex(model_graph,model_node)
        jump_node = add_node!(aggregate_model,index = nodeindex)
        m,var_map = _buildnodemodel!(aggregate_model,jump_node,model_node)
        var_maps[jump_node] = var_map
    end

    #LOCAL LINK CONSTRAINTS
    #inspect the link constraints, and map them to variables within flat model
    for linkconstraint in local_link_constraints
        #linkconstraint = LinkConstraint(link)
        indexmap = Dict() #{node variable => new jump model variable index} Need index of node variables to flat model variables
        vars = linkconstraint.terms.vars
        for var in vars
            model_node = getnode(var)
            var_index = JuMP.linearindex(var)                   #index in modelgraph node
            node_index = getindex(model_graph,model_node)       #node index in modelgraph
            jump_node = getnode(jump_graph,node_index)          #the corresponding jumpgraph jumpnode
            flat_indexmap = jump_node.indexmap
            indexmap[var] = flat_indexmap[var_index]            #modelnode variable => jumpnode variable index
        end
        t = []
        for terms in linearterms(linkconstraint.terms)
            push!(t,terms)
        end
        con_reference = @constraint(aggregate_model, linkconstraint.lb <= sum(t[i][1]*JuMP.Variable(aggregate_model,indexmap[(t[i][2])]) for i = 1:length(t)) + linkconstraint.terms.constant <= linkconstraint.ub)
        push!(jump_graph.linkconstraints,con_reference)
    end

    #CREATE NEW AGGREGATED NODE
    aggregate_node = add_node!(model_graph)
    setmodel(aggregate_node,aggregate_model)
    #
    #GLOBAL LINK CONSTRAINTS
    for linkconstraint in cross_link_constraints
        indexmap = Dict()
        vars = linkconstraint.terms.vars
        t = []
        for terms in linearterms(linkconstraint.terms)
            push!(t,terms)
        end

        t_new = []
        for i = 1:length(t)
            coeff = t[i][1]
            var = t[i][2]
            model_node = getnode(var)
            var_index = JuMP.linearindex(var)                   #index in modelgraph node
            node_index = getindex(model_graph,model_node)       #node index in modelgraph
            if !(getnode(var) in nodes)  #if it's on a different node not in this subset
                #node_model = getmodel(getnode(var))
                #push!(new_vars,var)
                push!(t_new,(coeff,var))
                #t[i][2] = var
            else #it's on the aggregate node
                #node_model = aggregate_model
                jump_node = getnode(jump_graph,node_index)          #the corresponding jumpgraph jumpnode
                flat_indexmap = jump_node.indexmap
                indexmap[var] = flat_indexmap[var_index]            #modelnode variable => jumpnode variable index
                new_var = JuMP.Variable(aggregate_model,indexmap[var])
                push!(t_new,(coeff,new_var))
                #t[i][2] = new_var
            end
        end
        @linkconstraint(model_graph, linkconstraint.lb <= sum(t[i][1]*t[i][2] for i = 1:length(t)) + linkconstraint.terms.constant <= linkconstraint.ub)
    end
    #
    # #DELETE AGGREGATED NODES
    # # for node in nodes
    # #     delete!(node)
    # # end
    #
    # #return local_link_constraints,cross_link_constraints
    return aggregate_model
end

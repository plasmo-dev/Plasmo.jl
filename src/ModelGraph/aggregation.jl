function get_local_and_cross_links(model_graph::ModelGraph,nodes::Vector{ModelNode})
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
    return local_link_constraints , cross_link_constraints
end

#Build up an aggregate model with given nodes.
function create_aggregate_model(model_graph::ModelGraph,nodes::Vector{ModelNode})
    local_links, cross_links = get_local_and_cross_links(model_graph,nodes)
    aggregate_model =  JuMPGraphModel()     #Use a JuMPGraphModel so we can track the internal structure
    jump_graph = getgraph(aggregate_model)

    #COPY NODE MODELS INTO AGGREGATE MODEL
    var_maps = Dict()
    for model_node in nodes  #for each node in the model graph
        nodeindex = getindex(model_graph,model_node)
        jump_node = add_node!(aggregate_model,index = nodeindex)
        m,var_map = _buildnodemodel!(aggregate_model,jump_node,model_node)  #build model nodes into new jump node.  var_map is a mapping of model node variable indices to new jump node variables
        var_maps[model_node] = var_map
    end

    #LOCAL LINK CONSTRAINTS
    #Inspect the link constraints and map them to variables within flat model
    for linkconstraint in local_links
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

    #OBJECTIVE
    @objective(aggregate_model,Min,sum(getobjective(node) for node in getnodes(jump_graph)))
    return aggregate_model,cross_links,var_maps
end

# function create_partitioned_model_graph(model_graph::ModelGraph,partitions::Vector{Any})
#     model_partitions = convert(Vector{Vector{ModelNode}},partitions)
#     return create_partitioned_model_graph(model_graph,model_partitions)
# end

# function create_partitioned_model_graph(model_graph::ModelGraph,partitions::Vector{Vector{Integer}})
#     model_partitions = Vector{Vector{ModelNode}}()
#     for partition in partitions
#         nodes = collectnodes(model_graph[[partition]])
#         push!(model_partitions,nodes)
#     end
#     return create_partitioned_model_graph(model_graph,model_partitions)
# end

# #Given a model graph and a set of node partitions, create a new aggregated model graph
# function create_partitioned_model_graph(model_graph::ModelGraph,partitions::Vector{Vector{ModelNode}})
#     new_model_graph = ModelGraph()
# 
#     aggregate_models = []
#     all_cross_links = []
#     variable_mapping = Dict()
#     all_var_maps = Dict()
#
#     #NOTE Need to catch objective terms
#     for partition in partitions  #create aggregate model for each partition
#         aggregate_model,cross_links,var_maps = create_aggregate_model(model_graph,partition)
#         push!(aggregate_models,aggregate_model)
#         append!(all_cross_links,cross_links)
#         merge!(all_var_maps,var_maps)
#     end
#     all_cross_links = unique(all_cross_links)  #remove duplicate cross links
#
#     agg_nodes = []
#     for agg_model in aggregate_models
#         aggregate_node = add_node!(new_model_graph)
#         setmodel(aggregate_node,agg_model)
#         push!(agg_nodes,aggregate_node)
#     end
#
#     #GLOBAL LINK CONSTRAINTS.  Re-add link constraints to aggregated model nodes
#     for linkconstraint in all_cross_links
#         linear_terms = []
#         for terms in linearterms(linkconstraint.terms)
#             push!(linear_terms,terms)
#         end
#
#         #Get references to variables in the aggregated models
#         t_new = []
#         for i = 1:length(linear_terms)
#             coeff = linear_terms[i][1]
#             var = linear_terms[i][2]
#             model_node = getnode(var)                #the original model node
#             var_index = JuMP.linearindex(var)        #variable index in the model node
#             var_map = all_var_maps[model_node]       #model node variable map {index => aggregate_variable}
#             agg_var = var_map[var_index]
#             push!(t_new,(coeff,agg_var))
#         end
#         @linkconstraint(new_model_graph, linkconstraint.lb <= sum(t_new[i][1]*t_new[i][2] for i = 1:length(t_new)) + linkconstraint.terms.constant <= linkconstraint.ub)
#     end
#     return new_model_graph , agg_nodes
# end


#Given a model graph and a set of node partitions, create a new aggregated model graph
function create_lifted_model_graph(model_graph::ModelGraph,partitions::Vector{Vector{ModelNode}})
    new_model_graph = ModelGraph()

    aggregate_models = []
    all_cross_links = []
    variable_mapping = Dict()
    all_var_maps = Dict()
    for partition in partitions  #create aggregate model for each partition
        aggregate_model,cross_links,var_maps = create_aggregate_model(model_graph,partition)
        push!(aggregate_models,aggregate_model)
        append!(all_cross_links,cross_links)
        merge!(all_var_maps,var_maps)
    end
    all_cross_links = unique(all_cross_links)  #remove duplicate cross links

    for agg_model in aggregate_models
        aggregate_node = add_node!(new_model_graph)
        setmodel(aggregate_node,agg_model)
    end

    sub_nodes = collectnodes(new_model_graph)
    #GLOBAL LINK CONSTRAINTS.  Re-add link constraints to aggregated model nodes
    master_node = add_node!(new_model_graph,Model())

    for linkconstraint in all_cross_links
        linear_terms = []
        for terms in linearterms(linkconstraint.terms)
            push!(linear_terms,terms)
        end

        #Get references to variables in the aggregated models
        t_new = []
        for i = 1:length(linear_terms)
            coeff = linear_terms[i][1]
            var = linear_terms[i][2]
            model_node = getnode(var)                #the original model node
            var_index = JuMP.linearindex(var)        #variable index in the model node
            var_map = all_var_maps[model_node]       #model node variable map {index => aggregate_variable}
            agg_var = var_map[var_index]
            push!(t_new,(coeff,agg_var))
        end

        #For simple links, create a single lifted variable and 2 linkconstraints
        if length(t_new) == 2 && (linkconstraint.lb == linkconstraint.ub) && (linear_terms[1][1]) == -linear_terms[2][1]
            lifted_var = @variable(getmodel(master_node))
            for term in t_new
                var = term[2]
                @linkconstraint(new_model_graph,lifted_var == var)
            end
#        end

        else  #else create multiple duplicates and lift the constraints into the master
            lift_terms = []
            for term in t_new
                coeff = term[1]
                var = term[2]
                lifted_var = @variable(getmodel(master_node) , start = JuMP.getvalue(var))
                @linkconstraint(new_model_graph,lifted_var == var)
                push!(lift_terms,(coeff,lifted_var))
            end
            @constraint(getmodel(master_node), linkconstraint.lb <= sum(lift_terms[i][1]*lift_terms[i][2] for i = 1:length(lift_terms)) + linkconstraint.terms.constant <= linkconstraint.ub)
        end

        #For simple links, create a single lifted variable and 2 linkconstraints
        @linkconstraint(new_model_graph, linkconstraint.lb <= sum(t_new[i][1]*t_new[i][2] for i = 1:length(t_new)) + linkconstraint.terms.constant <= linkconstraint.ub)
    end
    return new_model_graph , master_node, sub_nodes
end



#TODO
#Aggregate parts of a graph into a model node
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

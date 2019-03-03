mutable struct PipsTree <: AbstractModelGraph
    basegraph::BasePlasmoGraph                   #Model graph structure.  Put constraint references on edges
    linkmodel::LinkModel
    serial_model::Union{AbstractModel,Nothing}        #The internal serial model for the tree.  Returned if requested by the solve
    master_node_index::Int64
    sub_node_indices::Vector{Int64}
end
PipsTree(;solver = JuMP.UnsetSolver()) = PipsTree(BasePlasmoGraph(HyperGraph),LinkModel(;solver = solver),nothing,0,Vector{Int64}())

create_node(tree::PipsTree) = ModelNode()
create_edge(tree::PipsTree) = LinkingEdge()

function addmaster!(tree::PipsTree)
    basegraph = getbasegraph(tree)
    LightGraphs.add_vertex!(basegraph.lightgraph)
    index = LightGraphs.nv(basegraph.lightgraph)
    label = Symbol("node"*string(index))

    master = create_node(tree)                        #create a node for the given graph type
    basenode = getbasenode(master)
    basenode.indices[basegraph] = index             #Set the index of this node in this basegraph
    add_node!(basegraph.nodedict,master,index)

    tree.master_node_index = getindex(tree,master)
    return master
end

function getmaster(tree::PipsTree)
    if tree.master_node_index != 0
        return getnode(tree,tree.master_node_index)
    else
        return nothing
    end
end


#Add a node to a PipsTree
function add_node!(tree::PipsTree)
    #Extend from base method
    basegraph = getbasegraph(tree)
    LightGraphs.add_vertex!(basegraph.lightgraph)
    index = LightGraphs.nv(basegraph.lightgraph)
    label = Symbol("node"*string(index))

    node = create_node(tree)                        #create a node for the given graph type
    basenode = getbasenode(node)
    basenode.indices[basegraph] = index             #Set the index of this node in this basegraph
    add_node!(basegraph.nodedict,node,index)

    #NEW STUFF
    push!(tree.sub_node_indices,getindex(tree,node))
    return node
end

#Create a Pips tree from a model graph
#master partition is the optional first stage problem
function create_pips_tree(model_graph::ModelGraph,partitions::Vector{Vector{Int64}};master_partition = Vector{Int64}(),lift_link_constraints = false)
    pips_tree = PipsTree()

    #aggregate_models = []
    all_cross_links = []
    variable_mapping = Dict()
    all_var_maps = Dict()

    #TODO map tree variables back to indices of original variables
    if !isempty(master_partition)
        partition_nodes = [getnode(model_graph,index) for index in master_partition]
        aggregate_model,cross_links,var_maps = create_aggregate_model(model_graph,partition_nodes)

        append!(all_cross_links,cross_links)
        merge!(all_var_maps,var_maps)

        aggregate_master = add_master!(pips_tree)
        setmodel(aggregate_master,agg_model)
    end

    #NOTE Need to catch objective terms
    for partition in partitions  #create aggregate model for each partition
        partition_nodes = [getnode(model_graph,index) for index in partition]
        aggregate_model,cross_links,var_maps = create_aggregate_model(model_graph,partition_nodes)
        #push!(aggregate_models,aggregate_model)
        append!(all_cross_links,cross_links)
        merge!(all_var_maps,var_maps)

        aggregate_node = add_node!(pips_tree)
        setmodel(aggregate_node,aggregate_model)
    end
    all_cross_links = unique(all_cross_links)  #remove duplicate cross links

    #GLOBAL LINK CONSTRAINTS.  Re-add link constraints to aggregated model nodes
    if !lift_link_constraints
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
            @linkconstraint(pips_tree, linkconstraint.lb <= sum(t_new[i][1]*t_new[i][2] for i = 1:length(t_new)) + linkconstraint.terms.constant <= linkconstraint.ub)
        end
    #LIFTED LINK CONSTRAINTS.  #lift the linkconstraints on each subnode
    else
        #The IDEA Create ghost copies of variables for every node.  Create local copies of constraints.  Then create linkconstraints that make all the ghost copies
        #the same across every node (i.e. nonanticipitivity constraints).
        for linkconstraint in all_cross_links  #lift each link constraint
            #Grab coefficients and variables
            linear_terms = []
            for terms in linearterms(linkconstraint.terms)
                push!(linear_terms,terms)
            end
            agg_nodes = []
            #agg_vars = []
            new_linear_terms = [] #linear terms for new node constraint
            for term in linear_terms
                coeff = term[1]
                var = term[2]
                model_node = getnode(var)
                var_index = JuMP.linearindex(var)
                var_map = all_var_maps[model_node]
                agg_var = var_map[var_index]  #var in the aggregated partition
                push!(agg_nodes,getnode(agg_var))
                push!(new_linear_terms,(coeff,agg_var))
            end

            #Create local ghost variables on each agg_node for the corresponding constraint
            ghost_dict = Dict()  #index of linear term => ghost vars
            local_dict = Dict()
            #Add lifted constraint to each aggregated node
            for agg_node in agg_nodes
                local_linear_terms = []
                for i = 1:length(new_linear_terms)
                    agg_var = new_linear_terms[i][2]
                    agg_col = agg_var.col
                    if getnode(agg_var) != agg_node                     #if the variable belongs to a different node
                        ghost_var = @variable(getmodel(agg_node))       #create a ghost variable
                        setlowerbound(ghost_var,agg_var.m.colLower[agg_col])
                        setupperbound(ghost_var,agg_var.m.colUpper[agg_col])
                        setcategory(ghost_var,agg_var.m.colCat[agg_col])
                        setvalue(ghost_var,getvalue(agg_var))

                        push!(local_linear_terms,(new_linear_terms[i][1],ghost_var))                #swap out variable
                        if haskey(ghost_dict,i)
                            push!(ghost_dict[i],ghost_var)
                        else
                            ghost_dict[i] = [ghost_var]
                        end
                    else
                        push!(local_linear_terms,(new_linear_terms[i][1],new_linear_terms[i][2]))
                        local_dict[i] = new_linear_terms[i][2]
                    end
                end
                #add lifted constraint to node
                @constraint(getmodel(agg_node),linkconstraint.lb <= sum(local_linear_terms[i][1]*local_linear_terms[i][2] for i = 1:length(local_linear_terms)) +
                linkconstraint.terms.constant <= linkconstraint.ub)
            end

            #Get master node to make nonanticipitivity constraints
            master = getmaster(pips_tree)
            if master == nothing
                master = addmaster!(pips_tree)
                setmodel(master,Model())
            end

            #Add linkconstraint to force consensus among corresponding ghost and local variables
            for i = 1:length(new_linear_terms)
                if haskey(ghost_dict,i)         #if there are ghost vars for this term, create a master variable
                    ghost_master_var = @variable(getmodel(master))
                    local_var = local_dict[i]
                    local_col = local_var.col
                    setlowerbound(ghost_master_var,local_var.m.colLower[local_col])
                    setupperbound(ghost_master_var,local_var.m.colUpper[local_col])
                    setcategory(ghost_master_var,local_var.m.colCat[local_col])
                    setvalue(ghost_master_var,getvalue(local_var))
                    for ghost_var in ghost_dict[i]
                        @linkconstraint(pips_tree,ghost_master_var == ghost_var)
                    end
                    @linkconstraint(pips_tree,ghost_master_var == local_dict[i])
                end
            end
        end
    end
    return pips_tree
end

#Copy the solution from the aggregated
function setsolution(tree::PipsTree,graph::ModelGraph)
    for tree_node in getnodes(tree)
        model = getmodel(tree_node) #TODO IGNORE THE ROOT NODE IF IT WAS LIFTED
        if is_graphmodel(model)
            jump_graph = getgraph(model)
            for node in getnodes(model)
                index = getindex(jump_graph,node)
                node2 = getnode(graph,index)       #get the corresponding node in the original graph
                for i = 1:num_var(node)
                    node1_var = getnodevariable(node,i)
                    node2_var = getnodevariable(node2,i)
                    setvalue(node2_var,getvalue(node1_var))
                end
            end
        end
    end
end

function setsolution(graph1::PipsTree,graph2::PipsTree)
    for node in getnodes(graph1)
        index = getindex(graph1,node)
        node2 = getnode(graph2,index)       #get the corresponding node or edge in graph2
        for i = 1:num_var(node)
            node1_var = getnodevariable(node,i)
            node2_var = getnodevariable(node2,i)
            setvalue(node2_var,getvalue(node1_var))
        end
    end
end

#TODO
# Identifying shared entities
# Function to find link variables that show up in each link constraint
# function find_common_link_variables(graph::ModelGraph)
# end

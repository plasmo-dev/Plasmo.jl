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

function add_master!(tree::PipsTree)
    master = add_node!(tree)
    tree.master_node_index = getindex(tree,master)
    return master
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
function create_pips_tree(model_graph::ModelGraph,partitions::Vector{Vector{Int64}};master_partition = Vector{Int64}())
    pips_tree = PipsTree()

    #aggregate_models = []
    all_cross_links = []
    variable_mapping = Dict()
    all_var_maps = Dict()

    #TODO map tree variables back to indices of original variables
    if !isempty(master_partition)
        partition_nodes = [getnode(model_graph,index) for index in master_partition]
        aggregate_model,cross_links,var_maps = create_aggregate_model(model_graph,partition_nodes)
        #push!(aggregate_models,aggregate_model)
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
    return pips_tree
end

#Copy the solution from the aggregated
function setsolution(tree::PipsTree,graph::ModelGraph)
    for tree_node in getnodes(tree)
        model = getmodel(tree_node)
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
#Function to find link variables that show up in many
# function find_common_link_variables(graph::ModelGraph)
# end

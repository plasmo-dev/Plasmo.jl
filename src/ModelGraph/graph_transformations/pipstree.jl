mutable struct PipsStruct <: AbstractModelGraph
    basegraph::BasePlasmoGraph                   #Model graph structure.  Put constraint references on edges
    linkmodel::LinkModel
    serial_model::Nullable{AbstractModel}        #The internal serial model for the tree.  Returned if requested by the solve
    master_node_index::Int64
    sub_node_indices::Vector{Int64}
end
PipsStruct(;solver = JuMP.UnsetSolver()) = PipsStruct(BasePlasmoGraph(HyperGraph),LinkModel(;solver = solver),Nullable(),Vector{Vector{ModelNode}}(),Dict{ModelNode,Int}())

create_node(pstruct::PipsStruct) = ModelNode()
create_edge(pstruct::PipsStruct) = LinkingEdge()

#Create a Pips tree from a model graph
function create_pips_tree(model_graph::ModelGraph,partitions::Vector{Vector{Int64}})
    pips_tree = PipsTree()

    aggregate_models = []
    all_cross_links = []
    variable_mapping = Dict()
    all_var_maps = Dict()

    #NOTE Need to catch objective terms
    for partition in partitions  #create aggregate model for each partition
        aggregate_model,cross_links,var_maps = create_aggregate_model(model_graph,partition)
        push!(aggregate_models,aggregate_model)
        append!(all_cross_links,cross_links)
        merge!(all_var_maps,var_maps)
    end
    all_cross_links = unique(all_cross_links)  #remove duplicate cross links

    agg_nodes = []
    for agg_model in aggregate_models
        aggregate_node = add_node!(new_model_graph)
        setmodel(aggregate_node,agg_model)
        push!(agg_nodes,aggregate_node)
    end

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
        @linkconstraint(new_model_graph, linkconstraint.lb <= sum(t_new[i][1]*t_new[i][2] for i = 1:length(t_new)) + linkconstraint.terms.constant <= linkconstraint.ub)
    end
    return new_model_graph , agg_nodes
end

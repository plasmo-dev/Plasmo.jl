##############################################################################
# ModelGraph
##############################################################################
"""
ModelGraph()

The ModelGraph Type.  Represents a graph containing models (nodes) and the linkconstraints (edges) between them.
"""
mutable struct ModelGraph <: AbstractModelGraph

    #Topology
    modelnodes::Vector{ModelNode}                #Local model nodes
    linkedges::Vector{LinkEdge}                  #Local link edges.  These can also connect nodes across subgraphs
    node_idx_map::Dict{ModelNode,Int64}          #Local map of model nodes to indices
    edge_idx_map::Dict{LinkEdge,Int64}           #Local map of link edges indices
    subgraphs::Vector{AbstractModelGraph}        #Subgraphs contained in the model graph

    #graphindex::Int64
    linkedge_map::OrderedDict{Set,LinkEdge}      #Sets of vertices map to a linkedge

    #Objective
    objective_sense::MOI.OptimizationSense
    objective_function::JuMP.AbstractJuMPScalar

    #Optimizer
    optimizer

    #Object indices
    linkeqconstraint_index::Int           #keep track of constraint indices
    linkineqconstraint_index::Int
    linkconstraint_index::Int

    #Model Information
    obj_dict::Dict{Symbol,Any}

    #TODO Nonlinear Link Constraints using NLP Data
    nlp_data::Union{Nothing,JuMP._NLPData}

    #Constructor
    function ModelGraph()
        modelgraph = new(Vector{ModelNode}(),
                    Vector{LinkEdge}(),
                    Dict{ModelNode,Int64}(),
                    Dict{LinkEdge,Int64}(),
                    Vector{ModelGraph}(),
                    OrderedDict{OrderedSet,LinkEdge}(),
                    MOI.FEASIBILITY_SENSE,
                    zero(JuMP.GenericAffExpr{Float64, JuMP.AbstractVariableRef}),
                    nothing,
                    0,
                    0,
                    0,
                    Dict{Symbol,Any}(),
                    nothing
                    )
        return modelgraph
    end
end


########################################################
# ModelGraph Interface
########################################################
#################
#Subgraphs
#################
function add_subgraph!(graph::ModelGraph,subgraph::ModelGraph)
    push!(graph.subgraphs,subgraph)
    return graph
end
getsubgraphs(modelgraph::ModelGraph) = modelgraph.subgraphs

#Recursively grab subgraphs in the given modelgraph
function all_subgraphs(modelgraph::ModelGraph)
    subgraphs = modelgraph.subgraphs
    for subgraph in subgraphs
        subgraphs = [subgraphs;all_subgraphs(subgraph)]
    end
    return subgraphs
end
#################
#ModelNodes
#################
function add_node!(graph::ModelGraph)
    modelnode = ModelNode()
    push!(graph.modelnodes,modelnode)
    i = length(graph.modelnodes)
    modelnode.label = "$i"
    graph.node_idx_map[modelnode] = length(graph.modelnodes)
    return modelnode
end

function add_node!(graph::ModelGraph,m::JuMP.Model)
    node = add_node!(graph)
    set_model(node,m)
    return node
end

function add_node!(graph::ModelGraph,modelnode::ModelNode)
    push!(graph.modelnodes,modelnode)
    graph.node_idx_map[modelnode] = length(graph.modelnodes)
    return modelnode
end

getnodes(graph::ModelGraph) = graph.modelnodes
getnode(graph::ModelGraph,index::Int64) = graph.modelnodes[index]

#Recursively collect nodes in a modelgraph from each of its subgraphs
function all_nodes(graph::ModelGraph)
    nodes = graph.modelnodes
    for subgraph in graph.subgraphs
        nodes = [nodes;all_nodes(subgraph)]
    end
    return nodes
end

#Find a node from recursive collection of modelgraph nodes.
function find_node(graph::ModelGraph,index::Int64)
    nodes = all_nodes(graph)
    return nodes[index]
end

function Base.getindex(graph::ModelGraph,node::ModelNode)
    return graph.node_idx_map[node]
end

###################################################
#LinkEdges
###################################################
function add_link_edge!(graph::ModelGraph,modelnodes::Vector{ModelNode})
    #Check for existing linkedge.  Return if edge already exists
    key = Set(modelnodes)
    if haskey(graph.linkedge_map,key)
        linkedge = graph.linkedge_map[key]
    else
        linkedge = LinkEdge(modelnodes)
        push!(graph.linkedges,linkedge)
        n_links = length(graph.linkedges)
        idx = n_links + 1
        graph.linkedge_map[linkedge.nodes] = linkedge
        graph.edge_idx_map[linkedge] = idx
    end
    return linkedge
end
add_edge!(graph::ModelGraph,modelnodes::Vector{ModelNode}) = add_link_edge!(graph,modelnodes)

getedges(graph::ModelGraph) = graph.linkedges
getedge(graph::ModelGraph,index::Int64) = graph.linkedges[index]
function all_edges(graph::ModelGraph)
    edges = getedges(graph)
    for subgraph in graph.subgraphs
        edges = [edges;all_edges(subgraph)]
    end
    return edges
end
getedge(graph::ModelGraph,nodes::OrderedSet{ModelNode}) = graph.linkedge_map[nodes]

function getedge(graph::ModelGraph,nodes::ModelNode...)
    s = Set(collect(nodes))
    return getlinkedge(graph,s)
end

function Base.getindex(graph::ModelGraph,linkedge::LinkEdge)
    return graph.edge_idx_map[linkedge]
end

# function getedge(graph::ModelGraph,vertices::Int...)
#     s = Set(collect(vertices))
#     return getlinkedge(graph,s)
# end

########################################################
# Model Management
########################################################
#is_master_model(model::JuMP.Model) = haskey(model.ext,:modelgraph)
has_objective(graph::ModelGraph) = graph.objective_function != zero(JuMP.GenericAffExpr{Float64, JuMP.AbstractVariableRef})
has_NLobjective(graph::ModelGraph) = graph.nlp_data != nothing && graph.nlp_data.nlobj != nothing
has_subgraphs(graph::ModelGraph) = !(isempty(graph.subgraphs))
has_NLlinkconstraints(graph::ModelGraph) = graph.nlp_data != nothing && !(isempty(graph.nlp_data.nlconstr))

num_linkconstraints(graph::ModelGraph) = sum(num_linkconstraints.(graph.linkedges))  #length(graph.linkeqconstraints) + length(graph.linkineqconstraints)
num_NLlinkconstraints(graph::ModelGraph) = graph.nlp_data == nothing ? 0 : length(graph.nlp_data.nlconstr)

num_nodes(graph::ModelGraph) = length(graph.modelnodes)
num_linkedges(graph::ModelGraph) = length(graph.linkedges)
getnumnodes(graph::ModelGraph) = num_nodes(graph)

function num_all_nodes(graph::ModelGraph)
    n_nodes = sum(num_nodes.(all_subgraphs(graph)))
    n_nodes += num_nodes(graph)
    return n_nodes
end

function num_all_linkedges(graph::ModelGraph)
    n_link_edges = sum(num_linkedges.(all_subgraphs(graph)))
    n_link_edges += num_linkedges(graph)
    return n_link_edges
end

function getlinkconstraints(graph::ModelGraph)
    links = LinkConstraint[]
    for ledge in graph.linkedges
        append!(links,collect(values(ledge.linkconstraints)))
    end
    return links
end

#Go through subgraphs and get all linkconstraints
function all_linkconstraints(graph::ModelGraph)
    links = LinkConstraint[]
    for subgraph in all_subgraphs(graph)
        append!(links,getlinkconstraints(subgraph))
    end
    append!(links,getlinkconstraints(graph))
    return links
end

function num_all_linkconstraints(graph::ModelGraph)
    return length(all_linkconstraints(graph))
end

function num_all_variables(graph::ModelGraph)
    n_node_variables = sum(JuMP.num_variables.(all_nodes(graph)))
    return n_node_variables
end

function num_all_constraints(graph::ModelGraph)
    n_node_constraints = sum(JuMP.num_constraints.(all_nodes(graph)))
    return n_node_constraints
end

function JuMP.num_variables(graph::ModelGraph)
    n_node_variables = sum(JuMP.num_variables.(getnodes(graph)))
    return n_node_variables
end
function JuMP.num_constraints(graph::ModelGraph)
    n_node_constraints = sum(JuMP.num_constraints.(getnodes(graph)))
    return n_node_constraints
end

#JuMP Model Extenstion
####################################
# Objective
###################################
JuMP.objective_function(graph::ModelGraph) = graph.objective_function
JuMP.set_objective_function(graph::ModelGraph, x::JuMP.VariableRef) = JuMP.set_objective_function(graph, convert(AffExpr,x))
JuMP.set_objective_function(graph::ModelGraph, func::JuMP.AbstractJuMPScalar) = graph.objective_function = func  #JuMP.set_objective_function(graph, func)

function JuMP.set_objective(graph::ModelGraph, sense::MOI.OptimizationSense, func::JuMP.AbstractJuMPScalar)
    graph.objective_sense = sense
    graph.objective_function = func
end

function JuMP.objective_value(graph::ModelGraph)
    objective = JuMP.objective_function(graph)
    return nodevalue(objective)
    #return(value,graph,objective)
end

# nodevalue(lvref::LinkVariableRef) = JuMP.
JuMP.object_dictionary(m::ModelGraph) = m.obj_dict
JuMP.objective_sense(m::ModelGraph) = m.objective_sense

# Model Extras
JuMP.show_constraints_summary(::IOContext,m::ModelGraph) = ""
JuMP.show_backend_summary(::IOContext,m::ModelGraph) = ""

#####################################################
#  Link Constraints
#  A linear constraint between JuMP Models (nodes).  Link constraints can be equality or inequality.
#####################################################


function add_link_equality_constraint(graph::ModelGraph,con::JuMP.ScalarConstraint,name::String = "")
    @assert isa(con.set,MOI.EqualTo)  #EQUALITY CONSTRAINTS

    graph.linkeqconstraint_index += 1
    graph.linkconstraint_index += 1

    link_con = LinkConstraint(con)    #Convert ScalarConstraint to a LinkConstraint
    modelnodes = getnodes(link_con)

    linkedge = add_link_edge!(graph,modelnodes)

    cref = LinkConstraintRef(graph.linkconstraint_index,linkedge)
    JuMP.set_name(cref, name)

    push!(linkedge.linkrefs,cref)

    linkedge.linkconstraints[cref.idx] = link_con
    eq_idx = graph.linkeqconstraint_index
    linkedge.linkeqconstraints[eq_idx] = link_con

    #Add partial linkconstraint to nodes
    for (var,coeff) in link_con.func.terms
      node = getnode(var)
      _add_to_partial_linkeqconstraint!(node,var,coeff,link_con.func.constant,link_con.set,eq_idx)
    end

    return cref
end

function add_link_inequality_constraint(graph::ModelGraph,con::JuMP.ScalarConstraint,name::String = "")
    @assert typeof(con.set) in [MOI.Interval{Float64},MOI.LessThan{Float64},MOI.GreaterThan{Float64}]

    graph.linkineqconstraint_index += 1
    graph.linkconstraint_index += 1

    link_con = LinkConstraint(con)    #Convert ScalarConstraint to a LinkConstraint
    modelnodes = getnodes(link_con)
    linkedge = add_link_edge!(graph,modelnodes)

    cref = LinkConstraintRef(graph.linkconstraint_index,linkedge)
    JuMP.set_name(cref, name)
    push!(linkedge.linkrefs,cref)

    linkedge.linkconstraints[cref.idx] = link_con
    ineq_idx = graph.linkineqconstraint_index
    linkedge.linkineqconstraints[ineq_idx] = link_con

    #Add partial linkconstraint to nodes
    for (var,coeff) in link_con.func.terms
      node = getnode(var)
      _add_to_partial_linkineqconstraint!(node,var,coeff,link_con.func.constant,link_con.set,ineq_idx)
    end

    return cref
end

function JuMP.add_constraint(graph::ModelGraph, con::JuMP.ScalarConstraint, name::String="")
    if isa(con.set,MOI.EqualTo)
        cref = add_link_equality_constraint(graph,con,name)
    else
        cref = add_link_inequality_constraint(graph,con,name)
    end
    return cref
end

#Add to a partial linkconstraint on a modelnode
function _add_to_partial_linkeqconstraint!(node::ModelNode,var::JuMP.VariableRef,coeff::Number,constant::Float64,set::MOI.AbstractScalarSet,index::Int64)
    @assert getnode(var) == node
    if haskey(node.partial_linkeqconstraints,index)
        linkcon = node.partial_linkeqconstraints[index]
        JuMP.add_to_expression!(linkcon.func,coeff,var)
    else
        new_func = JuMP.GenericAffExpr{Float64,JuMP.VariableRef}()
        new_func.terms[var] = coeff
        new_func.constant = constant
        linkcon = LinkConstraint(new_func,set)
        node.partial_linkeqconstraints[index] = linkcon
    end
end

#Add to a partial linkconstraint on a modelnode
function _add_to_partial_linkineqconstraint!(node::ModelNode,var::JuMP.VariableRef,coeff::Number,constant::Float64,set::MOI.AbstractScalarSet,index::Int64)
    @assert getnode(var) == node
    if haskey(node.partial_linkineqconstraints,index)
        linkcon = node.partial_linkineqconstraints[index]
        JuMP.add_to_expression!(linkcon.func,coeff,var)
    else
        new_func = JuMP.GenericAffExpr{Float64,JuMP.VariableRef}()
        new_func.terms[var] = coeff
        new_func.constant = constant
        linkcon = LinkConstraint(new_func,set)
        node.partial_linkineqconstraints[index] = linkcon
    end
end

function JuMP.add_constraint(graph::ModelGraph, con::JuMP.AbstractConstraint, name::String="")
    error("Cannot add constraint $con. A ModelGraph currently only supports Scalar LinkConstraints")
end

JuMP.owner_model(cref::LinkConstraintRef) = cref.linkedge
# JuMP.constraint_type(::ModelGraph) = LinkConstraintRef
JuMP.constraint_type(::ModelGraph) = LinkConstraintRef
JuMP.jump_function(constraint::LinkConstraint) = constraint.func
JuMP.moi_set(constraint::LinkConstraint) = constraint.set
JuMP.shape(::LinkConstraint) = JuMP.ScalarShape()
function JuMP.constraint_object(cref::LinkConstraintRef, F::Type, S::Type)
   con = cref.linkedge.linkconstraints[cref.idx]
   con.func::F
   con.set::S
   return con
end
JuMP.set_name(cref::LinkConstraintRef, s::String) = JuMP.owner_model(cref).linkconstraint_names[cref.idx] = s
JuMP.name(con::LinkConstraintRef) =  JuMP.owner_model(con).linkconstraint_names[con.idx]

function MOI.delete!(graph::ModelGraph, cref::LinkConstraintRef)
    delete!(graph.linkconstraints, cref.idx)
    delete!(graph.linkconstraint_names, cref.idx)
end
MOI.is_valid(graph::ModelGraph, cref::LinkConstraintRef) = cref.idx in keys(graph.linkconstraints)

#######################################################
# HIERARCHICAL CONSTRAINTS
#######################################################
#TODO: These are just constraints between a child node and a parent node


#################################
# Optimizer
#################################
set_optimizer(graph::ModelGraph,optimizer) = graph.optimizer = optimizer

####################################
#Print Functions
####################################
function string(graph::ModelGraph)
    """
    Model Graph:
    local nodes: $(getnumnodes(graph)), total nodes: $(length(all_nodes(graph)))
    local link constraints: $(num_linkconstraints(graph)), total link constraints $(length(all_linkconstraints(graph)))
    local subgraphs: $(length(getsubgraphs(graph))), total subgraphs $(length(all_subgraphs(graph)))
    """
end
print(io::IO, graph::ModelGraph) = print(io, string(graph))
show(io::IO,graph::ModelGraph) = print(io,graph)

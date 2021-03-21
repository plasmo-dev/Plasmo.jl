"""
    HyperGraphBackend

Graph backend corresponding to a `LightGraphs` HyperGraph object.  A `HyperGraphBackend` is used to do graph analysis on an optigraph
by mapping optigraph elements to hypergraph elements.
"""
mutable struct HyperGraphBackend
    hypergraph::HyperGraph
    hyper_map::Dict
    update_backend::Bool  #flag that graph backend needs to be re-created when querying graph attributes
end
##############################################################################
# OptiGraph
##############################################################################
"""
    OptiGraph()

Create an empty OptiGraph. An OptiGraph extends JuMP.AbstractModel and supports most JuMP.Model functions.
"""
mutable struct OptiGraph <: AbstractOptiGraph #<: JuMP.AbstractModel  (OptiGraph ultimately extends a JuMP model to use its syntax)
    #Topology
    optinodes::Vector{OptiNode}                  #Local model nodes
    optiedges::Vector{OptiEdge}                  #Local link edges.  These can also connect nodes across subgraphs
    node_idx_map::Dict{OptiNode,Int64}           #Local map of model nodes to indices
    edge_idx_map::Dict{OptiEdge,Int64}           #Local map of link edges indices
    subgraphs::Vector{AbstractOptiGraph}         #Subgraphs contained in the model graph
    optiedge_map::OrderedDict{Set,OptiEdge}      #Sets of optinodes that map to an optiedge

    #Objective
    objective_sense::MOI.OptimizationSense
    objective_function::JuMP.AbstractJuMPScalar

    # IDEA: moi_backend interfaces with solvers.  For standard optimization solvers, we aggregate a MOI backend on the fly using optinodes
    moi_backend::Union{Nothing,MOI.ModelLike} #could just make this the optimizer.

    #IDEA: graph_backend used for graph functions (e.g. neighbors)
    graph_backend::Union{Nothing,HyperGraphBackend}

    bridge_types::Set{Any}
    optimizer::Any #NOTE: MadNLP uses the optimizer field.  This could also be used by parallel solvers to store objects

    obj_dict::Dict{Symbol,Any}

    #Extension Information
    ext::Dict{Symbol,Any}

    id::Symbol

    #TODO Someday
    #Capture nonlinear linking constraints and (separable) nonlinear objective functions
    #nlp_data::Union{Nothing,JuMP._NLPData}

    #Constructor
    function OptiGraph()
        caching_mode = MOIU.AUTOMATIC
        universal_fallback = MOIU.UniversalFallback(MOIU.Model{Float64}())
        backend = MOIU.CachingOptimizer(universal_fallback,caching_mode)

        optigraph = new(Vector{OptiNode}(),
                    Vector{OptiEdge}(),
                    Dict{OptiNode,Int64}(),
                    Dict{OptiEdge,Int64}(),
                    Vector{OptiGraph}(),
                    OrderedDict{OrderedSet,OptiEdge}(),
                    MOI.FEASIBILITY_SENSE,
                    zero(JuMP.GenericAffExpr{Float64, JuMP.AbstractVariableRef}),
                    backend,
                    nothing,
                    Set{Any}(),
                    nothing,
                    Dict{Symbol,Any}(),
                    Dict{Symbol,Any}(),
                    gensym()
                    )
        return optigraph
    end
end

#Create an OptiGraph given a set of optinodes and optiedges
function OptiGraph(nodes::Vector{OptiNode},edges::Vector{OptiEdge})
    is_valid_optigraph(nodes,edges) || error("Cannot create optigraph from given nodes and edges.  At least one edge node is not in the provided vector of optinodes.")
    graph = OptiGraph()
    for node in nodes
        add_node!(graph,node)
    end
    for edge in edges
        push!(graph.optiedges,edge)
    end
    graph.node_idx_map = Dict([(node,i) for (i,node) in enumerate(nodes)])
    graph.edge_idx_map = Dict([(edge,i) for (i,edge) in enumerate(edges)])
    return graph
end

function _is_valid_optigraph(nodes::Vector{OptiNode},edges::Vector{OptiEdge})
    edge_nodes = union(getnodes.(edges)...)
    return issubset(edge_nodes,nodes)
end


@deprecate ModelGraph OptiGraph

########################################################
# OptiGraph Interface
########################################################
#Backend Check
function _flag_graph_backend!(graph::OptiGraph)
    if graph.graph_backend != nothing
        graph.graph_backend.update_backend = true
    end
end

#################
#Subgraphs
#################
"""
    add_subgraph!(graph::OptiGraph,subgraph::OptiGraph)

Add the sub-optigraph `subgraph` to the higher level optigraph `graph`. Returns the original `graph`
"""
function add_subgraph!(graph::OptiGraph,subgraph::OptiGraph)
    push!(graph.subgraphs,subgraph)
    _flag_graph_backend!(graph)
    return graph
end

"""
    getsubgraphs(optigraph::OptiGraph)::Vector{OptiGraph}

Retrieve the local subgraphs of `optigraph`.
"""
getsubgraphs(optigraph::OptiGraph) = OptiGraph[subgraph for subgraph in optigraph.subgraphs]
num_subgraphs(optigraph::OptiGraph) = length(optigraph.subgraphs)

"""
    all_subgraphs(optigraph::OptiGraph)::Vector{OptiGraph}

Retrieve all of the contained subgraphs of `optigraph`, including nested subgraphs. The order of the subgraphs in
the returned vector starts with the local subgraphs in `optigraph` and then appends the nested subgraphs for each local subgraph.
"""
function all_subgraphs(optigraph::OptiGraph)
    subgraphs = optigraph.subgraphs
    for subgraph in subgraphs
        subgraphs = [subgraphs;all_subgraphs(subgraph)]
    end
    return subgraphs
end
num_all_subgraphs(optigraph::OptiGraph) = length(all_subgraphs(optigraph))
has_subgraphs(graph::OptiGraph) = !(isempty(graph.subgraphs))
#################
#OptiNodes
#################
"""
    add_node!(graph::OptiGraph)

Create a new `OptiNode` and add it to `graph`. Returns the added optinode.

    add_node!(graph::OptiGraph,m::JuMP.Model)

Add a new optinode to `graph` and set its model to the `JuMP.Model` `m`.

    add_node!(graph::OptiGraph,optinode::OptiNode)

Add the existing `optinode` (Created with `OptiNode()`) to `graph`.
"""
function add_node!(graph::OptiGraph)
    optinode = OptiNode()
    i = length(graph.optinodes) + 1
    optinode.label = "n$i"
    #graph.node_idx_map[optinode] = length(graph.optinodes)
    add_node!(graph,optinode)
    return optinode
end

function add_node!(graph::OptiGraph,m::JuMP.Model)
    optinode = add_node!(graph)
    set_model(node,m)
    return node
end

function add_node!(graph::OptiGraph,optinode::OptiNode)
    push!(graph.optinodes,optinode)
    graph.node_idx_map[optinode] = length(graph.optinodes)
    _flag_graph_backend!(graph)
    return optinode
end

"""
    getnodes(graph::OptiGraph) = graph.optinodes

Retrieve the optinodes in `graph`.
"""
getnodes(graph::OptiGraph) = graph.optinodes

"""
    getnode(graph::OptiGraph) = graph.optinodes

Retrieve the local optinode in `graph` at `index`. This does not look up nodes that could be in subgraphs.
"""
getnode(graph::OptiGraph,index::Int64) = graph.optinodes[index]

"""
    all_nodes(graph::OptiGraph)

Recursively collect nodes in a optigraph from each of its subgraphs
"""
function all_nodes(graph::OptiGraph)
    nodes = graph.optinodes
    for subgraph in graph.subgraphs
        nodes = [nodes;all_nodes(subgraph)]
    end
    return nodes
end

"""
    all_node(graph::OptiGraph,index::Int64)

Find the optinode in `graph` at `index`. This traverses all of the nodes in the subgraphs of `graph`.
"""
function all_node(graph::OptiGraph,index::Int64)
    nodes = all_nodes(graph)
    return nodes[index]
end
@deprecate(find_node,all_node)


"""
    Base.getindex(graph::OptiGraph,node::OptiNode)

Retrieve the index of the optinode `node` in `graph`.
"""
function Base.getindex(graph::OptiGraph,node::OptiNode)
    return graph.node_idx_map[node]
end

###################################################
#OptiEdges
###################################################
function add_optiedge!(graph::OptiGraph,optinodes::Vector{OptiNode})
    #Check for existing optiedge.  Return if edge already exists
    key = Set(optinodes)
    if haskey(graph.optiedge_map,key)
        optiedge = graph.optiedge_map[key]
    else
        optiedge = OptiEdge(optinodes)
        push!(graph.optiedges,optiedge)
        n_links = length(graph.optiedges)
        idx = n_links + 1
        graph.optiedge_map[optiedge.nodes] = optiedge
        graph.edge_idx_map[optiedge] = idx
        _flag_graph_backend!(graph)
    end
    return optiedge
end
add_edge!(graph::OptiGraph,optinodes::Vector{OptiNode}) = add_optiedge!(graph,optinodes)
@deprecate add_link_edge add_optiedge

"""
    getedges(graph::OptiGraph) = graph.optiedges

Retrieve the local optiedges in `graph`.
"""
getedges(graph::OptiGraph) = graph.optiedges

"""
    getedge(graph::OptiGraph,index::Int64)

Retrieve the local optiedge in `graph` at `index`

    getedge(graph::OptiGraph,nodes::OrderedSet{OptiNode})

Retrieve the optiedge in `graph` that connects the optinodes in the OrderedSet of `nodes`.

    getedge(graph::OptiGraph,nodes::OptiNode...)

Retrieve the optiedge in `graph` that connects `nodes`.
"""
getedge(graph::OptiGraph,index::Int64) = graph.optiedges[index]
getedge(graph::OptiGraph,nodes::OrderedSet{OptiNode}) = graph.optiedge_map[nodes]
function getedge(graph::OptiGraph,nodes::OptiNode...)
    s = Set(collect(nodes))
    return getoptiedge(graph,s)
end

"""
    all_edges(graph::OptiGraph)

Retrieve all optiedges in `graph`, includes edges in subgraphs of `graph`.
"""
function all_edges(graph::OptiGraph)
    edges = getedges(graph)
    for subgraph in graph.subgraphs
        edges = [edges;all_edges(subgraph)]
    end
    return edges
end

function all_edge(graph::OptiGraph,index::Int64)
    edges = all_nodes(graph)
    return edges[index]
end

"""
    Base.getindex(graph::OptiGraph,optiedge::OptiEdge)

Retrieve the index of the `optiedge` in `graph`.
"""
function Base.getindex(graph::OptiGraph,optiedge::OptiEdge)
    return graph.edge_idx_map[optiedge]
end

function num_all_nodes(graph::OptiGraph)
    n_nodes = sum(num_nodes.(all_subgraphs(graph)))
    n_nodes += num_nodes(graph)
    return n_nodes
end

function num_all_optiedges(graph::OptiGraph)
    n_link_edges = sum(num_optiedges.(all_subgraphs(graph)))
    n_link_edges += num_optiedges(graph)
    return n_link_edges
end

num_nodes(graph::OptiGraph) = length(graph.optinodes)
@deprecate getnumnodes num_nodes
num_optiedges(graph::OptiGraph) = length(graph.optiedges)
########################################################
# OptiGraph Model Interaction
########################################################
has_objective(graph::OptiGraph) = graph.objective_function != zero(JuMP.AffExpr) && graph.objective_function != zero(JuMP.QuadExpr)
has_node_objective(graph::OptiGraph) = any(has_objective.(all_nodes(graph)))
has_quad_objective(graph::OptiGraph) = any((node) -> isa(objective_function(node),JuMP.QuadExpr),all_nodes(graph))
has_nlp_data(graph::OptiGraph) = any(node -> (node.nlp_data !== nothing),all_nodes(graph))
function has_nl_objective(graph::OptiGraph)
    for node in all_nodes(graph)
        if node.nlp_data != nothing
            if node.nlp_data.nlobj != nothing
                return true
            end
        end
    end
    return false
end

JuMP.object_dictionary(graph::OptiGraph) = graph.obj_dict
JuMP.show_constraints_summary(::IOContext,m::OptiGraph) = ""
JuMP.show_backend_summary(::IOContext,m::OptiGraph) = ""
JuMP.list_of_constraint_types(graph::OptiGraph) = unique(vcat(JuMP.list_of_constraint_types.(all_nodes(graph))...))
JuMP.all_constraints(graph::OptiGraph,F::DataType,S::DataType) = vcat(JuMP.all_constraints.(all_nodes(graph),Ref(F),Ref(S))...)

function JuMP.all_variables(graph::OptiGraph)
    vars = vcat([JuMP.all_variables(node) for node in all_nodes(graph)]...)
    return vars
end
"""
    getlinkconstraints(graph::OptiGraph)::Vector{LinkConstraintRef}

Retrieve the local linking constraints in `graph`. Returns a vector of the linking constraints.
"""
function getlinkconstraints(graph::OptiGraph)
    links = LinkConstraintRef[]
    for edge in graph.optiedges
        # append!(links,collect(values(ledge.linkconstraints)))
        append!(links,edge.linkrefs)
    end
    return links
end
num_linkconstraints(graph::OptiGraph) = sum(num_linkconstraints.(graph.optiedges))
"""
    all_linkconstraints(graph::OptiGraph)::Vector{LinkConstraintRef}

Retrieve all of the linking constraints in `graph`, including linking constraints in its subgraphs. Returns a vector of the linking constraints.
"""
function all_linkconstraints(graph::OptiGraph)
    links = LinkConstraintRef[]
    for subgraph in all_subgraphs(graph)
        append!(links,getlinkconstraints(subgraph))
    end
    append!(links,getlinkconstraints(graph))
    return links
end

function num_all_linkconstraints(graph::OptiGraph)
    return length(all_linkconstraints(graph))
end

function num_all_variables(graph::OptiGraph)
    n_node_variables = sum(JuMP.num_variables.(all_nodes(graph)))
    return n_node_variables
end

function num_all_constraints(graph::OptiGraph)
    n_node_constraints = sum(JuMP.num_constraints.(all_nodes(graph)))
    return n_node_constraints
end

"""
    JuMP.num_variables(graph::OptiGraph)

Retrieve the number of local node variables in `graph`. Does not include variables in subgraphs.
"""
function JuMP.num_variables(graph::OptiGraph)
    n_node_variables = sum(JuMP.num_variables.(getnodes(graph)))
    return n_node_variables
end

"""
    JuMP.num_constraints(graph::OptiGraph)

Retrieve the number of local node constraints in `graph`. Does not include constraints in subgraphs.
"""
function JuMP.num_constraints(graph::OptiGraph)
    n_node_constraints = sum(JuMP.num_constraints.(getnodes(graph)))
    return n_node_constraints
end

#JuMP Model Extenstion
####################################
# Objective
###################################
JuMP.objective_sense(graph::OptiGraph) = graph.objective_sense
JuMP.set_objective_sense(graph::OptiGraph,sense::MOI.OptimizationSense) = graph.objective_sense = sense
"""
    JuMP.objective_function(graph::OptiGraph)

Retrieve the current graph objective function.
"""
JuMP.objective_function(graph::OptiGraph) = graph.objective_function
function JuMP.set_objective_function(graph::OptiGraph, x::JuMP.VariableRef)
    x_affine = convert(JuMP.AffExpr,x)
    JuMP.set_objective_function(graph,x_affine)
end

function JuMP.set_objective_function(graph::OptiGraph,expr::JuMP.GenericAffExpr)
    #clear optinodes objective functions
    for node in all_nodes(graph)
        JuMP.set_objective_function(node,0)
    end
    #put objective terms onto nodes
    for (coef,term) in JuMP.linear_terms(expr)
        node = getnode(term)
        JuMP.set_objective_function(node,objective_function(node) + coef*term)
    end
    graph.objective_function = expr
end

function JuMP.set_objective_function(graph::OptiGraph,expr::JuMP.GenericQuadExpr)
    for node in all_nodes(graph)
        JuMP.set_objective_function(node,0)
    end
    for (coef,term1,term2) in JuMP.quad_terms(expr)
        @assert getnode(term1) == getnode(term2)
        node = getnode(term1)
        JuMP.set_objective_function(node,objective_function(node) + coef*term1*term2)
    end
    for (coef,term) in JuMP.linear_terms(expr)
        node = getnode(term)
        JuMP.set_objective_function(node,objective_function(node) + coef*term)
    end
    graph.objective_function = expr
end

function JuMP.set_objective(graph::OptiGraph, sense::MOI.OptimizationSense, func::JuMP.AbstractJuMPScalar)
    JuMP.set_objective_sense(graph,sense)
    JuMP.set_objective_function(graph,func)
end

function JuMP.objective_value(graph::OptiGraph)
    objective = JuMP.objective_function(graph)
    return value(objective)
end

function getnodes(expr::JuMP.GenericAffExpr)
    nodes = OptiNode[]
    for (coef,term) in JuMP.linear_terms(expr)
        node = getnode(term)
        push!(nodes,node)
    end
    return unique(nodes)
end

function getnodes(expr::JuMP.GenericQuadExpr)
    nodes = OptiNode[]
    for (coef,term1,term2) in JuMP.quad_terms(expr)
        @assert getnode(term1) == getnode(term2)
        node = getnode(term1)
        push!(nodes,node)
    end
    for (coef,term) in JuMP.linear_terms(expr)
        node = getnode(term)
        push!(nodes,node)
    end
    return unique(nodes)
end

#####################################################
#  Link Constraints
#  A linear constraint between optinodes.  Link constraints can be equality or inequality.
#####################################################
function JuMP.add_constraint(graph::OptiGraph, con::JuMP.AbstractConstraint, name::String="")
    error("Cannot add constraint $con. An OptiGraph currently only supports Scalar LinkConstraints")
end

function JuMP.add_constraint(graph::OptiGraph, con::JuMP.ScalarConstraint, name::String="";attached_node = getnode(collect(keys(con.func.terms))[1]))
    cref = add_link_constraint(graph,con,name,attached_node = attached_node)
    return cref
end

JuMP._valid_model(m::OptiEdge, name) = nothing
function JuMP.add_constraint(optiedge::OptiEdge, con::JuMP.ScalarConstraint, name::String="";attached_node = getnode(collect(keys(con.func.terms))[1]))
    cref = add_link_constraint(optiedge,con,name,attached_node = attached_node)
    return cref
end

#Create optiedge and add linkconstraint
function add_link_constraint(graph::OptiGraph,con::JuMP.ScalarConstraint,name::String = "";attached_node = nothing)
    optinodes = getnodes(con)
    optiedge = add_optiedge!(graph,optinodes)
    cref = JuMP.add_constraint(optiedge,con,name,attached_node = attached_node)
    return cref
end

#Add linkconstraint directly to optiedge
function add_link_constraint(optiedge::OptiEdge,con::JuMP.ScalarConstraint,name::String = "";attached_node = nothing)
    typeof(con.set) in [MOI.Interval{Float64},MOI.LessThan{Float64},MOI.GreaterThan{Float64},MOI.EqualTo{Float64}] || error("Unsupported link constraint set of type $(con.set)")

    link_con = LinkConstraint(con)    #Convert ScalarConstraint to a LinkConstraint
    link_con.attached_node = attached_node

    optinodes = getnodes(link_con)
    @assert issubset(optinodes,optiedge.nodes)

    linkconstraint_index = length(optiedge.linkconstraints) + 1
    cref = LinkConstraintRef(linkconstraint_index,optiedge)
    JuMP.set_name(cref, name)
    push!(optiedge.linkrefs,cref)
    optiedge.linkconstraints[linkconstraint_index] = link_con


    #Add partial linkconstraint to nodes
    node_partial_indices = Dict(node => length(node.partial_linkconstraints) + 1 for node in optiedge.nodes)
    for (var,coeff) in link_con.func.terms
      node = getnode(var)
      index = node_partial_indices[node] #index of current linkconstraint for this node
      _add_to_partial_linkconstraint!(node,var,coeff,link_con.func.constant,link_con.set,index)
    end

    return cref
end

#Add partial link constraint to supporting optinodes
function _add_to_partial_linkconstraint!(node::OptiNode,var::JuMP.VariableRef,coeff::Number,constant::Float64,set::MOI.AbstractScalarSet,index::Int64)
    @assert getnode(var) == node
    #multiple variables might be on the same node, so check here
    if haskey(node.partial_linkconstraints,index)
        linkcon = node.partial_linkconstraints[index]
        JuMP.add_to_expression!(linkcon.func,coeff,var)
        constant == linkcon.func.constant || error("Found a Link Constraint constant mismatch when adding partial constraint to optinode")
        set == linkcon.set || error("Found a Link Constraint set mismatch when adding partial constraint to optinode")
    else #create a new partial constraint
        node_func = JuMP.GenericAffExpr{Float64,JuMP.VariableRef}()
        node_func.terms[var] = coeff
        node_func.constant = constant
        linkcon = LinkConstraint(node_func,set,node)
        node.partial_linkconstraints[index] = linkcon
    end
end


JuMP.constraint_type(::OptiGraph) = LinkConstraintRef
function JuMP.add_bridge(graph::OptiGraph,BridgeType::Type{<:MOI.Bridges.AbstractBridge})
    push!(graph.bridge_types, BridgeType)
    #_moi_add_bridge(JuMP.backend(model), BridgeType)
    return
end
####################################
#Print Functions
####################################
function string(graph::OptiGraph)
    """
    OptiGraph:
    local nodes: $(num_nodes(graph)), total nodes: $(length(all_nodes(graph)))
    local link constraints: $(num_linkconstraints(graph)), total link constraints $(length(all_linkconstraints(graph)))
    local subgraphs: $(length(getsubgraphs(graph))), total subgraphs $(length(all_subgraphs(graph)))
    """
end
print(io::IO, graph::OptiGraph) = print(io, string(graph))
show(io::IO,graph::OptiGraph) = print(io,graph)

"""
    empty!(graph::OptiGraph) -> graph
Empty the optigraph, that is, remove all variables, constraints and model
attributes but not optimizer attributes. Always return the argument.
Note: removes extensions data.
"""
function Base.empty!(graph::OptiGraph)::OptiGraph
    MOI.empty!(graph.moi_backend)
    empty!(graph.obj_dict)
    empty!(graph.ext)

    graph.optinodes = Vector{OptiNode}()
    graph.optiedges = Vector{OptiEdge}()
    graph.node_idx_map = Dict{OptiNode,Int64}()
    graph.edge_idx_map = Dict{OptiEdge,Int64}()
    graph.subgraphs = Vector{AbstractOptiGraph}()

    graph.optiedge_map = OrderedDict{Set,OptiEdge}()

    #Objective
    graph.objective_sense = MOI.FEASIBILITY_SENSE
    graph.objective_function = zero(JuMP.GenericAffExpr{Float64, JuMP.AbstractVariableRef})

    return graph
end

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

    # IDEA: Use MOI backend to interface with solvers.  We can create a backend on the fly when creating from induced optigraphs
    # NOTE: The NLPBlock points back to a NLP Evaluator
    moi_backend::Union{Nothing,MOI.ModelLike} #The backend can be created on the fly if we create an induced subgraph

    obj_dict::Dict{Symbol,Any}

    #Extension Information
    ext::Dict{Symbol,Any}

    #TODO Nonlinear Link Constraints or objective function using NLPData and NLPEvaluator
    #Also used for MOI backend when aggregating models
    nlp_data::Union{Nothing,JuMP._NLPData}

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
                    Dict{Symbol,Any}(),
                    Dict{Symbol,Any}(),
                    nothing
                    )
        return optigraph
    end
end



@deprecate ModelGraph OptiGraph

########################################################
# OptiGraph Interface
########################################################
#################
#Subgraphs
#################
"""
    add_subgraph!(graph::OptiGraph,subgraph::OptiGraph)

Add the sub-optigraph `subgraph` to the higher level optigraph `graph`. Returns the original `graph`
"""
function add_subgraph!(graph::OptiGraph,subgraph::OptiGraph)
    push!(graph.subgraphs,subgraph)
    return graph
end

"""
    getsubgraphs(optigraph::OptiGraph)::Vector{OptiGraph}

Retrieve the local subgraphs of `optigraph`.
"""
getsubgraphs(optigraph::OptiGraph) = optigraph.subgraphs

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
    push!(graph.optinodes,optinode)
    i = length(graph.optinodes)
    optinode.label = "$i"
    graph.node_idx_map[optinode] = length(graph.optinodes)
    return optinode
end

function add_node!(graph::OptiGraph,m::JuMP.Model)
    node = add_node!(graph)
    set_model(node,m)
    return node
end

function add_node!(graph::OptiGraph,optinode::OptiNode)
    push!(graph.optinodes,optinode)
    graph.node_idx_map[optinode] = length(graph.optinodes)
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
    find_node(graph::OptiGraph,index::Int64)

Find the optinode in `graph` at `index`. This traverses all of the nodes in the subgraphs of `graph`.
"""
function find_node(graph::OptiGraph,index::Int64)
    nodes = all_nodes(graph)
    return nodes[index]
end

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
function add_link_edge!(graph::OptiGraph,optinodes::Vector{OptiNode})
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
    end
    return optiedge
end
add_edge!(graph::OptiGraph,optinodes::Vector{OptiNode}) = add_link_edge!(graph,optinodes)

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

"""
    Base.getindex(graph::OptiGraph,optiedge::OptiEdge)

Retrieve the index of the `optiedge` in `graph`.
"""
function Base.getindex(graph::OptiGraph,optiedge::OptiEdge)
    return graph.edge_idx_map[optiedge]
end

########################################################
# Model Management
########################################################
has_objective(graph::OptiGraph) = graph.objective_function != zero(JuMP.GenericAffExpr{Float64, JuMP.AbstractVariableRef})
has_NLobjective(graph::OptiGraph) = graph.nlp_data != nothing && graph.nlp_data.nlobj != nothing
has_subgraphs(graph::OptiGraph) = !(isempty(graph.subgraphs))
has_NLlinkconstraints(graph::OptiGraph) = graph.nlp_data != nothing && !(isempty(graph.nlp_data.nlconstr))

num_linkconstraints(graph::OptiGraph) = sum(num_linkconstraints.(graph.optiedges))  #length(graph.linkeqconstraints) + length(graph.linkineqconstraints)
num_NLlinkconstraints(graph::OptiGraph) = graph.nlp_data == nothing ? 0 : length(graph.nlp_data.nlconstr)

num_nodes(graph::OptiGraph) = length(graph.optinodes)
num_optiedges(graph::OptiGraph) = length(graph.optiedges)
getnumnodes(graph::OptiGraph) = num_nodes(graph)

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

"""
    getlinkconstraints(graph::OptiGraph)::Vector{LinkConstraint}

Retrieve the local linking constraints in `graph`. Returns a vector of the linking constraints.
"""
function getlinkconstraints(graph::OptiGraph)
    links = LinkConstraint[]
    for ledge in graph.optiedges
        append!(links,collect(values(ledge.linkconstraints)))
    end
    return links
end

"""
    all_linkconstraints(graph::OptiGraph)::Vector{LinkConstraint}

Retrieve all of the linking constraints in `graph`, including linking constraints in its subgraphs. Returns a vector of the linking constraints.
"""
function all_linkconstraints(graph::OptiGraph)
    links = LinkConstraint[]
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
"""
    JuMP.objective_function(graph::OptiGraph)

Retrieve the current graph objective function.
"""
JuMP.objective_function(graph::OptiGraph) = graph.objective_function
JuMP.set_objective_function(graph::OptiGraph, x::JuMP.VariableRef) = JuMP.set_objective_function(graph, convert(AffExpr,x))
JuMP.set_objective_function(graph::OptiGraph, func::JuMP.AbstractJuMPScalar) = graph.objective_function = func  #JuMP.set_objective_function(graph, func)

function JuMP.set_objective(graph::OptiGraph, sense::MOI.OptimizationSense, func::JuMP.AbstractJuMPScalar)
    graph.objective_sense = sense
    graph.objective_function = func
end

function JuMP.objective_value(graph::OptiGraph)
    objective = JuMP.objective_function(graph)
    return nodevalue(objective)
end

JuMP.object_dictionary(m::OptiGraph) = m.obj_dict
JuMP.objective_sense(m::OptiGraph) = m.objective_sense

# Model Extras
JuMP.show_constraints_summary(::IOContext,m::OptiGraph) = ""
JuMP.show_backend_summary(::IOContext,m::OptiGraph) = ""

#####################################################
#  Link Constraints
#  A linear constraint between JuMP Models (nodes).  Link constraints can be equality or inequality.
#####################################################
function add_link_equality_constraint(graph::OptiGraph,con::JuMP.ScalarConstraint;name::String = "",attached_node = nothing)
    @assert isa(con.set,MOI.EqualTo)  #EQUALITY CONSTRAINTS


    link_con = LinkConstraint(con)    #Convert ScalarConstraint to a LinkConstraint
    link_con.attached_node = attached_node
    optinodes = getnodes(link_con)

    optiedge = add_link_edge!(graph,optinodes)

    linkconstraint_index = length(optiedge.linkconstraints) + 1
    linkeqconstraint_index = length(optiedge.linkeqconstraints) + 1
    cref = LinkConstraintRef(linkconstraint_index,optiedge)
    JuMP.set_name(cref, name)

    push!(optiedge.linkrefs,cref)

    optiedge.linkconstraints[linkconstraint_index] = link_con
    optiedge.linkeqconstraints[linkeqconstraint_index] = link_con

    #Add partial linkconstraint to nodes
    for (var,coeff) in link_con.func.terms
      node = getnode(var)
      _add_to_partial_linkeqconstraint!(node,var,coeff,link_con.func.constant,link_con.set,linkeqconstraint_index)
    end

    return cref
end

function add_link_inequality_constraint(graph::OptiGraph,con::JuMP.ScalarConstraint;name::String = "",attached_node = nothing)
    @assert typeof(con.set) in [MOI.Interval{Float64},MOI.LessThan{Float64},MOI.GreaterThan{Float64}]


    link_con = LinkConstraint(con)    #Convert ScalarConstraint to a LinkConstraint
    optinodes = getnodes(link_con)
    optiedge = add_link_edge!(graph,optinodes)
    linkconstraint_index = length(optiedge.linkconstraints) + 1
    linkineqconstraint_index = length(optiedge.linkeqconstraints) + 1
    link_con.attached_node = attached_node

    cref = LinkConstraintRef(linkconstraint_index,optiedge)
    JuMP.set_name(cref, name)
    push!(optiedge.linkrefs,cref)

    optiedge.linkconstraints[linkineqconstraint_index] = link_con
    optiedge.linkineqconstraints[linkineqconstraint_index] = link_con

    #Add partial linkconstraint to nodes
    for (var,coeff) in link_con.func.terms
      node = getnode(var)
      _add_to_partial_linkineqconstraint!(node,var,coeff,link_con.func.constant,link_con.set,linkineqconstraint_index)
    end

    return cref
end

function add_link_equality_constraint(optiedge::OptiEdge,con::JuMP.ScalarConstraint;name::String = "",attached_node = nothing)
    @assert isa(con.set,MOI.EqualTo)  #EQUALITY CONSTRAINTS

    link_con = LinkConstraint(con)    #Convert ScalarConstraint to a LinkConstraint
    link_con.attached_node = attached_node
    optinodes = getnodes(link_con)

    @assert issubset(optinodes,optiedge.nodes)

    linkconstraint_index = length(optiedge.linkconstraints) + 1
    linkeqconstraint_index = length(optiedge.linkeqconstraints) + 1
    cref = LinkConstraintRef(linkconstraint_index,optiedge)
    JuMP.set_name(cref, name)

    push!(optiedge.linkrefs,cref)

    optiedge.linkconstraints[linkconstraint_index] = link_con
    optiedge.linkeqconstraints[linkeqconstraint_index] = link_con

    #Add partial linkconstraint to nodes
    for (var,coeff) in link_con.func.terms
      node = getnode(var)
      _add_to_partial_linkeqconstraint!(node,var,coeff,link_con.func.constant,link_con.set,linkeqconstraint_index)
    end

    return cref
end

function add_link_inequality_constraint(optiedge::OptiEdge,con::JuMP.ScalarConstraint;name::String = "",attached_node = nothing)
    @assert typeof(con.set) in [MOI.Interval{Float64},MOI.LessThan{Float64},MOI.GreaterThan{Float64}]


    link_con = LinkConstraint(con)    #Convert ScalarConstraint to a LinkConstraint
    optinodes = getnodes(link_con)
    link_con.attached_node = attached_node

    @assert issubset(optinodes,optiedge.nodes)

    linkconstraint_index = length(optiedge.linkconstraints) + 1
    linkineqconstraint_index = length(optiedge.linkeqconstraints) + 1
    cref = LinkConstraintRef(linkconstraint_index,optiedge)
    JuMP.set_name(cref, name)

    push!(optiedge.linkrefs,cref)

    optiedge.linkconstraints[linkineqconstraint_index] = link_con
    optiedge.linkineqconstraints[linkineqconstraint_index] = link_con

    #Add partial linkconstraint to nodes
    for (var,coeff) in link_con.func.terms
      node = getnode(var)
      _add_to_partial_linkineqconstraint!(node,var,coeff,link_con.func.constant,link_con.set,linkineqconstraint_index)
    end

    return cref
end

function JuMP.add_constraint(graph::OptiGraph, con::JuMP.ScalarConstraint, name::String="";attached_node = getnode(collect(keys(con.func.terms))[1]))
    if isa(con.set,MOI.EqualTo)
        cref = add_link_equality_constraint(graph,con;name = name,attached_node = attached_node)
    else
        cref = add_link_inequality_constraint(graph,con;name = name,attached_node = attached_node)
    end
    return cref
end

import JuMP: _valid_model
_valid_model(m::OptiEdge, name) = nothing
function JuMP.add_constraint(optiedge::OptiEdge, con::JuMP.ScalarConstraint, name::String="";attached_node = getnode(collect(keys(con.func.terms))[1]))
    if isa(con.set,MOI.EqualTo)
        cref = add_link_equality_constraint(optiedge,con;name = name,attached_node = attached_node)
    else
        cref = add_link_inequality_constraint(optiedge,con;name = name,attached_node = attached_node)
    end
    return cref
end

#Add to a partial linkconstraint on a optinode
function _add_to_partial_linkeqconstraint!(node::OptiNode,var::JuMP.VariableRef,coeff::Number,constant::Float64,set::MOI.AbstractScalarSet,index::Int64)
    @assert getnode(var) == node
    if haskey(node.partial_linkeqconstraints,index)
        linkcon = node.partial_linkeqconstraints[index]
        JuMP.add_to_expression!(linkcon.func,coeff,var)
    else
        new_func = JuMP.GenericAffExpr{Float64,JuMP.VariableRef}()
        new_func.terms[var] = coeff
        new_func.constant = constant
        linkcon = LinkConstraint(new_func,set,nothing)
        node.partial_linkeqconstraints[index] = linkcon
    end
end

#Add to a partial linkconstraint on a optinode
function _add_to_partial_linkineqconstraint!(node::OptiNode,var::JuMP.VariableRef,coeff::Number,constant::Float64,set::MOI.AbstractScalarSet,index::Int64)
    @assert getnode(var) == node
    if haskey(node.partial_linkineqconstraints,index)
        linkcon = node.partial_linkineqconstraints[index]
        JuMP.add_to_expression!(linkcon.func,coeff,var)
    else
        new_func = JuMP.GenericAffExpr{Float64,JuMP.VariableRef}()
        new_func.terms[var] = coeff
        new_func.constant = constant
        linkcon = LinkConstraint(new_func,set,nothing)
        node.partial_linkineqconstraints[index] = linkcon
    end
end

function JuMP.add_constraint(graph::OptiGraph, con::JuMP.AbstractConstraint, name::String="")
    error("Cannot add constraint $con. An OptiGraph currently only supports Scalar LinkConstraints")
end

JuMP.owner_model(cref::LinkConstraintRef) = cref.optiedge
JuMP.constraint_type(::OptiGraph) = LinkConstraintRef
JuMP.jump_function(constraint::LinkConstraint) = constraint.func
JuMP.moi_set(constraint::LinkConstraint) = constraint.set
JuMP.shape(::LinkConstraint) = JuMP.ScalarShape()
function JuMP.constraint_object(cref::LinkConstraintRef, F::Type, S::Type)
   con = cref.optiedge.linkconstraints[cref.idx]
   con.func::F
   con.set::S
   return con
end
JuMP.set_name(cref::LinkConstraintRef, s::String) = JuMP.owner_model(cref).linkconstraint_names[cref.idx] = s
JuMP.name(con::LinkConstraintRef) =  JuMP.owner_model(con).linkconstraint_names[con.idx]

function MOI.delete!(cref::LinkConstraintRef)
    delete!(cref.optiedge.linkconstraints, cref.idx)
    delete!(cref.optiedge.linkconstraint_names, cref.idx)
end
MOI.is_valid(cref::LinkConstraintRef) = haskey(cref.idx,cref.optiedge.linkconstraints)



####################################
#Print Functions
####################################
function string(graph::OptiGraph)
    """
    OptiGraph:
    local nodes: $(getnumnodes(graph)), total nodes: $(length(all_nodes(graph)))
    local link constraints: $(num_linkconstraints(graph)), total link constraints $(length(all_linkconstraints(graph)))
    local subgraphs: $(length(getsubgraphs(graph))), total subgraphs $(length(all_subgraphs(graph)))
    """
end
print(io::IO, graph::OptiGraph) = print(io, string(graph))
show(io::IO,graph::OptiGraph) = print(io,graph)



#
# Other new functions
#
"""
    empty!(graph::OptiGraph) -> graph
Empty the optigraph, that is, remove all variables, constraints and model
attributes but not optimizer attributes. Always return the argument.
Note: removes extensions data.
"""
function Base.empty!(graph::OptiGraph)::OptiGraph
    MOI.empty!(graph.moi_backend)
    graph.nlp_data = nothing

    empty!(graph.obj_dict)
    empty!(graph.ext)


    optinodes::Vector{OptiNode}                  #Local model nodes
    optiedges::Vector{OptiEdge}                  #Local link edges.  These can also connect nodes across subgraphs
    node_idx_map::Dict{OptiNode,Int64}           #Local map of model nodes to indices
    edge_idx_map::Dict{OptiEdge,Int64}           #Local map of link edges indices
    subgraphs::Vector{AbstractOptiGraph}         #Subgraphs contained in the model graph

    optiedge_map::OrderedDict{Set,OptiEdge}      #Sets of optinodes that map to an optiedge

    #Objective
    objective_sense::MOI.OptimizationSense
    objective_function::JuMP.AbstractJuMPScalar

    return graph
end

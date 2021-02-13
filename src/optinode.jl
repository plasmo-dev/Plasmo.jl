##############################################################################
# OptiNode
##############################################################################
"""
    OptiNode()

Creates an empty OptiNode.  Does not add it to a graph.
"""
mutable struct OptiNode <: JuMP.AbstractModel
    #The underlying optinode model
    model::JuMP.AbstractModel #JuMP.Model
    nodevariable_index::Int64
    nodevariables::OrderedDict{Int,AbstractVariableRef}
    nodevarnames::Dict{Int,String}
    label::String

    #TODO: Just store linkconstraints.  Make functions that can differentiate equality and inequality.
    partial_linkeqconstraints::Dict{Int64,AbstractLinkConstraint}
    partial_linkineqconstraints::Dict{Int64,AbstractLinkConstraint}

    #nlp_data is a reference to `model.nlp_data`
    nlp_data::Union{Nothing,JuMP._NLPData}

    #Extension data
    ext::Dict{Symbol,Any}

    function OptiNode()
        model = JuMP.Model()
        node_backend = NodeOptimizer(JuMP.backend(model))
        model.moi_backend = node_backend
        node = new(model,
        0,
        OrderedDict{Int,JuMP.VariableRef}(),
        Dict{Int,String}(),
        "node",
        Dict{Int64,AbstractLinkConstraint}(),
        Dict{Int64,AbstractLinkConstraint}(),
        nothing,
        Dict{Symbol,Any}())
        node.model.ext[:optinode] = node

        return node
    end
end

#############################################
# OptiNode Management
############################################
"""
    JuMP.value(node::OptiNode,vref::VariableRef)

Get the variable value of `vref` on the optinode `node`.
"""
JuMP.value(node::OptiNode,vref::VariableRef) = node.variable_values[vref]
getmodel(node::OptiNode) = node.model
getnodevariable(node::OptiNode,index::Integer) = JuMP.VariableRef(getmodel(node),MOI.VariableIndex(index))

"""
    JuMP.all_variables(node::OptiNode)::Vector{JuMP.VariableRef}

Retrieve all of the variables on the optinode `node`.
"""
JuMP.all_variables(node::OptiNode) = JuMP.all_variables(getmodel(node))

setattribute(node::OptiNode,symbol::Symbol,attribute::Any) = getmodel(node).obj_dict[symbol] = attribute
getattribute(node::OptiNode,symbol::Symbol) = getmodel(node).obj_dict[symbol]

#TODO deprecate nodevalue and nodedual
"""
    nodevalue(var::JuMP.VariableRef)

Get the current value of `var`

    nodevalue(expr::JuMP.GenericAffExpr)

Get the current value of `expr` which is `JuMP.GenericAffExpr`

    nodevalue(expr::JuMP.GenericQuadExpr)

Get the current value of `expr` which is a `JuMP.GenericQuadExpr`
"""
nodevalue(var::JuMP.VariableRef) = JuMP.value(var)
function nodevalue(expr::JuMP.GenericAffExpr)
    ret_value = 0.0
    for (var,coeff) in expr.terms
        ret_value += coeff*nodevalue(var)
    end
    ret_value += expr.constant
    return ret_value
end
function nodevalue(expr::JuMP.GenericQuadExpr)
    ret_value = 0.0
    for (pair,coeff) in expr.terms
        ret_value += coeff*nodevalue(pair.a)*nodevalue(pair.b)
    end
    ret_value += nodevalue(expr.aff)
    ret_value += expr.aff.constant
    return ret_value
end
nodedual(con_ref::JuMP.ConstraintRef{JuMP.Model,MOI.ConstraintIndex}) = getnode(con).constraint_dual_values[con]
nodedual(con_ref::JuMP.ConstraintRef{JuMP.Model,JuMP.NonlinearConstraintIndex}) = getnode(con).nl_constraint_dual_values[con]

@deprecate nodevalue value
@deprecate nodedual dual

#TODO: Nonlinear constraint duals
function JuMP.dual(c::JuMP.ConstraintRef{OptiNode,NonlinearConstraintIndex})
    JuMP._init_NLP(c.model)
    nldata::JuMP._NLPData = c.model.nlp_data
    # The array is cleared on every solve.
    if length(nldata.nlconstr_duals) != length(nldata.nlconstr)
        nldata.nlconstr_duals = MOI.get(c.model, MOI.NLPBlockDual())
    end
    return nldata.nlconstr_duals[c.index.value]
end
"""
    set_model(node::OptiNode,m::AbstractModel)

Set the model on a node.  This will delete any link-constraints the node is currently part of
"""
function set_model(node::OptiNode,m::JuMP.AbstractModel;preserve_links = false)
    !(is_set_to_node(m) && getmodel(node) == m) || error("Model $m is already asigned to another node")
    node.model = m
    m.ext[:optinode] = node
end
@deprecate setmodel set_model
"""
    is_node_variable(node::OptiNode,var::JuMP.AbstractVariableRef)

Checks whether the variable `var` belongs to the optinode `node`.
"""
is_node_variable(node::OptiNode,var::JuMP.AbstractVariableRef) = getmodel(node) == var.m
is_node_variable(var::JuMP.AbstractVariableRef) = haskey(var.model.ext[:optinode])
is_set_to_node(m::AbstractModel) = haskey(m.ext,:optinode)                      #checks whether a model is assigned to a node

#############################################
# JuMP Extension
############################################
function Base.getindex(node::OptiNode,symbol::Symbol)
    if haskey(node.model.obj_dict,symbol)
        return getmodel(node)[symbol]
    else
        return getattribute(node,symbol)
    end
end

function Base.setindex!(node::OptiNode,value::Any,symbol::Symbol)
    setattribute(node,symbol,value)
end

JuMP.object_dictionary(m::OptiNode) = m.model.obj_dict
JuMP.variable_type(::OptiNode) = JuMP.VariableRef
JuMP.constraint_type(::OptiNode) = JuMP.ConstraintRef

function JuMP.add_variable(node::OptiNode, v::JuMP.AbstractVariable, name::String="")
    jump_vref = JuMP.add_variable(node.model,v,name) #add the variable to the optinode
    JuMP.set_name(jump_vref, "$(node.label)[:$(JuMP.name(jump_vref))]")
    return jump_vref
end

function JuMP.add_constraint(node::OptiNode, con::JuMP.AbstractConstraint, name::String="")
    cref = JuMP.add_constraint(getmodel(node),con,name)
    return cref
end

JuMP.add_NL_constraint(node::OptiNode,expr::Expr) = JuMP.add_NL_constraint(getmodel(node),expr)

function JuMP.num_constraints(node::OptiNode)
    m = getmodel(node)
    num_cons = 0
    for (func,set) in JuMP.list_of_constraint_types(m)
        if func != JuMP.VariableRef
            num_cons += JuMP.num_constraints(m,func,set)
        end
    end
    num_cons += JuMP.num_nl_constraints(m)
    return num_cons
end

JuMP.num_nl_constraints(node::OptiNode) = JuMP.num_nl_constraints(node.model)

function num_linked_variables(node::OptiNode)
    partial_link_eq = node.partial_linkeqconstraints
    partial_link_ineq = node.partial_linkineqconstraints
    num_linked = 0
    vars = []
    for (idx,link) in partial_link_eq
        for var in keys(link.func.terms)
            if !(var in vars)
                push!(vars,var)
                num_linked += 1
            end
        end
    end
    return num_linked
end

function num_link_constraints(node::OptiNode)
    return length(node.partial_link_eq + node.partial_link_ineq)
end

JuMP.objective_function(node::OptiNode) = JuMP.objective_function(getmodel(node))
JuMP.objective_value(node::OptiNode) = JuMP.objective_value(getmodel(node))
JuMP.objective_sense(node::OptiNode) = JuMP.objective_sense(getmodel(node))
JuMP.num_variables(node::OptiNode) = JuMP.num_variables(getmodel(node))
JuMP.NLPEvaluator(node::OptiNode) = JuMP.NLPEvaluator(getmodel(node))

JuMP.set_objective(optinode::OptiNode, sense::MOI.OptimizationSense, func::JuMP.AbstractJuMPScalar) = JuMP.set_objective(getmodel(optinode),sense,func)
JuMP.set_objective_function(optinode::OptiNode,func::JuMP.AbstractJuMPScalar) = JuMP.set_objective_function(optinode.model,func)
JuMP.set_objective_function(optinode::OptiNode,real::Real) = JuMP.set_objective_function(optinode.model,real)
JuMP.set_objective_sense(optinode::OptiNode,sense::MOI.OptimizationSense) = JuMP.set_objective_sense(optinode.model,sense)

#TODO: check nlp objective
has_objective(node::OptiNode) = objective_function(node) != zero(JuMP.AffExpr) && objective_function(node) != zero(JuMP.QuadExpr)
function has_nl_objective(node::OptiNode)
    if node.nlp_data != nothing
        if node.nlp_data.nlobj != nothing
            return true
        end
    end
    return false
end

JuMP.termination_status(node::OptiNode) = JuMP.termination_status(getmodel(node))
JuMP.raw_status(node::OptiNode) = JuMP.raw_status(getmodel(node))
JuMP.primal_status(node::OptiNode) = JuMP.primal_status(getmodel(node))
JuMP.dual_status(node::OptiNode) = JuMP.dual_status(getmodel(node))
JuMP.solver_name(node::OptiNode) = JuMP.solver_name(getmodel(node))
JuMP.mode(node::OptiNode) = JuMP.mode(getmodel(node))

JuMP.list_of_constraint_types(node::OptiNode) = JuMP.list_of_constraint_types(getmodel(node))
JuMP.all_constraints(node::OptiNode,F::DataType,S::DataType) = JuMP.all_constraints(getmodel(node),F,S)
# JuMP.VariableRef(node::OptiNode,var::JuMP.VariableRef) = JuMP.VariableRef(getmodel(node),var)
##############################################
# Get OptiNode
##############################################
getnode(m::JuMP.Model) = m.ext[:optinode]

#Get the corresponding node for a JuMP variable reference
function getnode(var::JuMP.VariableRef)
    if haskey(var.model.ext,:optinode)
        return getnode(var.model)
    else
        error("variable $var does not belong to a optinode.  If you're trying to create a linkconstraint, make sure
        the owning model has been set to a node.")
    end
end

function getnode(con::JuMP.ConstraintRef)
    if haskey(con.model.ext,:optinode)
        return getnode(con.model)
    else
        error("constraint $con does not belong to a node")
    end
end
getnode(m::AbstractModel) = is_set_to_node(m) ? m.ext[:optinode] : throw(error("Only node models have associated graph nodes"))
getnode(var::JuMP.AbstractVariableRef) = JuMP.owner_model(var).ext[:optinode]

###############################################
# Printing
###############################################
function string(node::OptiNode)
    "OptiNode w/ $(JuMP.num_variables(node)) Variable(s)"
end
print(io::IO,node::OptiNode) = print(io, string(node))
show(io::IO,node::OptiNode) = print(io,node)

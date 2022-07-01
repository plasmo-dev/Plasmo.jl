##############################################################################
# OptiNode
##############################################################################
"""
    OptiNode()

Creates an empty `OptiNode`.  Does not add it to an `OptiGraph`.
"""
mutable struct OptiNode <: JuMP.AbstractModel
    model::JuMP.AbstractModel
    label::String                                               #what gets printed
    partial_linkconstraints::Dict{Int64,AbstractLinkConstraint} #local node contribution to link constraint

    # nlp_data is a reference to `model.nlp_data`
    #nlp_data::Union{Nothing,JuMP._NLPData}
    nlp_duals::DefaultDict{Symbol,OrderedDict{Int64,Float64}}

    # extension data
    ext::Dict{Symbol,Any}

    # unique identifier
    id::Symbol

    function OptiNode()
        model = JuMP.Model()
        id = gensym()
        node_backend = NodeBackend(JuMP.backend(model),id)
        model.moi_backend = node_backend
        node = new(model,
        "node",
        Dict{Int64,AbstractLinkConstraint}(),
        #nothing,
        DefaultDict{Symbol,OrderedDict{Int64,Float64}}(OrderedDict()),
        Dict{Symbol,Any}(),
        id)
        node.model.ext[:optinode] = node
        return node
    end
end

#############################################
# OptiNode Management
############################################
"""
    jump_model(node::OptiNode)

Get the underlying `JuMP.Model` from the optinode `node`.
"""
jump_model(node::OptiNode) = node.model
@deprecate getmodel jump_model

"""
    setlabel(node::OptiNode, label::Symbol)

Set the label for optinode `node` to `label`. This is what gets printed.
"""
set_label(node::OptiNode,label::String) = node.label = label


"""
    label(node::OptiNode)

Get the label for optinode `node`.
"""
label(node::OptiNode) = node.label

"""
    JuMP.all_variables(node::OptiNode)::Vector{JuMP.VariableRef}

Retrieve all of the variables on the optinode `node`.
"""
JuMP.all_variables(node::OptiNode) = JuMP.all_variables(jump_model(node))

"""
    JuMP.value(node::OptiNode, vref::VariableRef)

Get the variable value of `vref` on the optinode `node`. This value is always the
local node value, not the value the node variable takes when solved as part of a
larger `OptiGraph`.
"""
JuMP.value(node::OptiNode, vref::VariableRef) =
    MOI.get(
    JuMP.backend(node).result_location[node.id],
    MOI.VariablePrimal(),
    JuMP.index(vref)
    )

"""
    JuMP.dual(c::JuMP.ConstraintRef{OptiNode,NonlinearConstraintIndex})

Get the dual value on a nonlinear constraint on an `OptiNode`
"""
function JuMP.dual(c::JuMP.ConstraintRef{OptiNode,NonlinearConstraintIndex})
    node = c.model
    node_backend = JuMP.backend(node)
    return node.nlp_duals[node_backend.last_solution_id][c.index.value]
end

"""
    is_node_variable(node::OptiNode, vref::JuMP.AbstractVariableRef)

Checks whether the variable reference `vref` belongs to the optinode `node`.
"""
is_node_variable(node::OptiNode, vref::JuMP.AbstractVariableRef) = jump_model(node)==vref.model

"""
    is_node_variable(vref::JuMP.AbstractVariableRef)

Checks whether the variable reference `vref` belongs to any `OptiNode`.
"""
is_node_variable(var::JuMP.AbstractVariableRef) = haskey(var.model.ext,:optinode)

"""
    is_set_to_node(m::JuMP.AbstractModel)

Checks whether the JuMP model `m` is set to any `OptiNode`
"""
function is_set_to_node(m::JuMP.AbstractModel)
    if haskey(m.ext,:optinode)
        return isa(m.ext[:optinode],OptiNode)
    else
        return false
    end
end

"""
    set_model(node::OptiNode, m::AbstractModel)

Set the JuMP model `m` to optinode `node`.
"""
function set_model(node::OptiNode, m::JuMP.AbstractModel)#; preserve_links=false)
    !(is_set_to_node(m) && jump_model(node) == m) || error("Model $m is already asigned to another node")
    node.model = m
    m.ext[:optinode] = node
    node_backend = NodeBackend(JuMP.backend(m),node.id)
    m.moi_backend = node_backend
    #TODO: handle link constraints on node
end
@deprecate setmodel set_model

#############################################
# JuMP Extension Functions
############################################
"""
    Base.getindex(node::OptiNode, symbol::Symbol)

Support retrieving node attributes via symbol lookup. (e.g. node[:x])
"""
Base.getindex(node::OptiNode, symbol::Symbol) = jump_model(node)[symbol]

"""
    Base.setindex(node::OptiNode, value::Any, symbol::Symbol)

Support retrieving node attributes via symbol lookup. (e.g. node[:x])
"""
Base.setindex(node::OptiNode,
    value::Any,
    symbol::Symbol) = JuMP.object_dictionary(node)[symbol] = value

"""
    JuMP.object_dictionary(node::OptiNode)

Get the underlying object dictionary of optinode `node`
"""
JuMP.object_dictionary(node::OptiNode) = JuMP.object_dictionary(jump_model(node))

"""
    JuMP.add_variable(node::OptiNode, v::JuMP.AbstractVariable, name::String="")

Add variable `v` to optinode `node`. This function supports use of the `@variable` JuMP macro.
Optionally add a `base_name` to the variable for printing.
"""
function JuMP.add_variable(node::OptiNode, v::JuMP.AbstractVariable, base_name::String="")
    jump_vref = JuMP.add_variable(node.model,v,base_name)
    JuMP.set_name(jump_vref, "$(node.label)[:$(JuMP.name(jump_vref))]")
    return jump_vref
end

"""
    JuMP.add_constraint(node::OptiNode, con::JuMP.AbstractConstraint, base_name::String="")

Add a constraint `con` to optinode `node`. This function supports use of the @constraint JuMP macro.
"""
function JuMP.add_constraint(node::OptiNode, con::JuMP.AbstractConstraint, base_name::String="")
    cref = JuMP.add_constraint(jump_model(node),con,base_name)
    return cref
end

"""
    JuMP.add_nonlinear_constraint(node::OptiNode, expr::Expr)

Add a non-linear constraint to an optinode using a Julia expression.
"""
function JuMP.add_nonlinear_constraint(node::OptiNode, expr::Expr)
    con = JuMP.add_nonlinear_constraint(jump_model(node), expr)
    #re-sync NLP data
    #TODO: think about less hacky nlp_data after JuMP NLP update
    #node.nlp_data = node.model.nlp_data
    return con
end

"""
    JuMP.num_variables(node::OptiNode)

Get the number of variables on optinode `node`
"""
JuMP.num_variables(node::OptiNode) = JuMP.num_variables(jump_model(node))

"""
    num_linked_variables(node::OptiNode)

Return the number of node variables on `node` that are linked to other nodes
"""
function num_linked_variables(node::OptiNode)
    partial_link_cons = node.partial_linkconstraints
    num_linked = 0
    vars = []
    for (idx,link) in partial_link_cons
        for var in keys(link.func.terms)
            if !(var in vars)
                push!(vars,var)
                num_linked += 1
            end
        end
    end
    return num_linked
end

# constraints
"""
    JuMP.num_constraints(node::OptiNode)

Get the number of constraints on optinode `node`
"""
function JuMP.num_constraints(node::OptiNode)
    m = jump_model(node)
    num_cons = 0
    for (func,set) in JuMP.list_of_constraint_types(m)
        if func != JuMP.VariableRef
            num_cons += JuMP.num_constraints(m,func,set)
        end
    end
    num_cons += JuMP.num_nonlinear_constraints(m)
    return num_cons
end

"""
    JuMP.num_nonlinear_constraints(node::OptiNode)

Get the number of nonlinear constraints on optinode `node`
"""
JuMP.num_nonlinear_constraints(node::OptiNode) = JuMP.num_nonlinear_constraints(node.model)

"""
    JuMP.list_of_constraint_types(node::OptiNode)

Get a list of constraint types on optinode `node`
"""
JuMP.list_of_constraint_types(node::OptiNode) =
                                JuMP.list_of_constraint_types(jump_model(node))

"""
    JuMP.all_constraints(node::OptiNode,F::DataType,S::DataType)

Get all constraints on optinode `node` of function type `F` and set `S`
"""
JuMP.all_constraints(node::OptiNode,F::DataType,S::DataType) =
                            JuMP.all_constraints(jump_model(node),F,S)

"""
    num_linkconstraints(node::OptiNode)

Return the number of link-constraints incident to optinode `node`
"""
function num_linkconstraints(node::OptiNode)
    return length(node.partial_linkconstraints)
end
@deprecate num_link_constraints num_linkconstraints




"""
    has_objective(node::OptiNode)

Check whether optinode `node` has a non-empty linear or quadratic objective function
"""
has_objective(node::OptiNode) =
    objective_function(node) != zero(JuMP.AffExpr) &&
    objective_function(node) != zero(JuMP.QuadExpr)


JuMP.nonlinear_model(node::OptiNode) = JuMP.nonlinear_model(jump_model(node))

"""
    has_nl_objective(node::OptiNode)

Check whether optinode `node` has a nonlinear objective function
"""
function has_nl_objective(node::OptiNode)
    nlp_model = JuMP.nonlinear_model(node)
    if nlp_model != nothing
        if nlp_model.objective != nothing
            return true
        end
    end
    return false
end

#NOTE: we could probably loop through JuMP Model methods and define the OptiNode ones

# objective function
"""
    JuMP.objective_function(node::OptiNode)

Retrieve the objective function on optinode `node`
"""
JuMP.objective_function(node::OptiNode) = JuMP.objective_function(jump_model(node))
JuMP.objective_value(node::OptiNode) = JuMP.objective_value(jump_model(node))
JuMP.objective_sense(node::OptiNode) = JuMP.objective_sense(jump_model(node))

JuMP.set_objective(optinode::OptiNode,
                    sense::MOI.OptimizationSense,
                    func::JuMP.AbstractJuMPScalar) =
                    JuMP.set_objective(jump_model(optinode),sense,func)

"""
    JuMP.set_nonlinear_objective(optinode::OptiNode, sense::MOI.OptimizationSense, obj::Any)

Set a nonlinear objective on optinode `node`
"""
JuMP.set_nonlinear_objective(optinode::OptiNode,
                        sense::MOI.OptimizationSense,
                        obj::Any) =
                        JuMP.set_nonlinear_objective(optinode.model,sense,obj)

JuMP.set_objective_function(optinode::OptiNode,func::JuMP.AbstractJuMPScalar) =
                            JuMP.set_objective_function(optinode.model,func)

JuMP.set_objective_function(optinode::OptiNode,real::Real) =
                            JuMP.set_objective_function(optinode.model,real)

JuMP.set_objective_sense(optinode::OptiNode,sense::MOI.OptimizationSense) =
                            JuMP.set_objective_sense(optinode.model,sense)


# NLP evaluator
"""
    JuMP.NLPEvaluator(node::OptiNode)

Retrieve the underlying JuMP NLP evaluator on optinode `node`
"""
JuMP.NLPEvaluator(node::OptiNode; kwargs...) = JuMP.NLPEvaluator(jump_model(node); kwargs...)

# status functions
"""
    JuMP.termination_status(node::OptiNode)

Return the termination status on optinode `node`
"""
JuMP.termination_status(node::OptiNode) = JuMP.termination_status(jump_model(node))
JuMP.raw_status(node::OptiNode) = JuMP.raw_status(jump_model(node))
JuMP.primal_status(node::OptiNode) = JuMP.primal_status(jump_model(node))
JuMP.dual_status(node::OptiNode) = JuMP.dual_status(jump_model(node))
JuMP.solver_name(node::OptiNode) = JuMP.solver_name(jump_model(node))
JuMP.mode(node::OptiNode) = JuMP.mode(jump_model(node))
JuMP._moi_mode(node_backend::NodeBackend) = node_backend.optimizer.mode
JuMP._init_NLP(node::OptiNode) = JuMP._init_NLP(jump_model(node))


##############################################
# Get optinode from other objects
# Note that `optinode` does a lot of type piracy here. Hopefully this is ok but
# JuMP or other extensions defining `optinode` could cause problems
##############################################
"""
    optinode(m::JuMP.Model)

Retrieve the optinode corresponding to JuMP model `m`
"""
optinode(m::JuMP.Model) = m.ext[:optinode]

#Get the corresponding node for a JuMP variable reference
"""
    optinode(var::JuMP.VariableRef)

Retrieve the optinode corresponding to JuMP `VariableRef`
"""
function optinode(var::JuMP.VariableRef)
    if haskey(var.model.ext, :optinode)
        return optinode(var.model)
    else
        error("variable $var does not belong to a optinode.  If you're trying to create a linkconstraint, make sure
        the owning model has been set to a node.")
    end
end

"""
    optinode(var::JuMP.VariableRef)::OptiNode

Retrieve the optinode corresponding to JuMP `ConstraintRef`
"""
function optinode(con::JuMP.ConstraintRef)
    if haskey(con.model.ext,:optinode)
        return optinode(con.model)
    else
        error("constraint $con does not belong to a node")
    end
end

###############################################
# Printing
###############################################
function string(node::OptiNode)
    "OptiNode w/ $(JuMP.num_variables(node)) Variable(s) and $(JuMP.num_constraints(node)) Constraint(s)"
end
print(io::IO,node::OptiNode) = print(io, string(node))
show(io::IO,node::OptiNode) = print(io,node)


# function JuMP.nonlinear_constraint_string(node::OptiNode, mode, c::JuMP._NonlinearConstraint)
#     s = JuMP._sense(c)
#     nl = JuMP.nonlinear_expr_string(node.model, mode, c.terms)
#     if s == :range
#         out_str = "$(_string_round(c.lb)) " * _math_symbol(mode, :leq) *
#                   " $nl " * _math_symbol(mode, :leq) * " " * _string_round(c.ub)
#     else
#         if s == :<=
#             rel = JuMP._math_symbol(mode, :leq)
#         elseif s == :>=
#             rel = JuMP._math_symbol(mode, :geq)
#         else
#             rel = JuMP._math_symbol(mode, :eq)
#         end
#         out_str = string(nl, " ", rel, " ", JuMP._string_round(JuMP._rhs(c)))
#     end
#     return out_str
# end
#
# const NonlinearOptiNodeConstraintRef = ConstraintRef{OptiNode, NonlinearConstraintIndex}# where T <: OptiObject
# function Base.show(io::IO, c::NonlinearOptiNodeConstraintRef)
#     print(io, JuMP.nonlinear_constraint_string(c.model, MIME("text/plain"), c.model.nlp_data.nlconstr[c.index.value]))
# end
#
# function Base.show(io::IO, ::MIME"text/latex", c::NonlinearOptiNodeConstraintRef)
#     constraint = c.model.nlp_data.nlconstr[c.index.value]
#     print(io, JuMP._wrap_in_math_mode(JuMP.nonlinear_constraint_string(c.model, MIME"text/latex", constraint)))
# end

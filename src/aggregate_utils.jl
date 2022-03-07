#Check for nonlinear objective
# function _has_nonlinear_obj(m::JuMP.Model)
#     if m.nlp_data != nothing
#         if m.nlp_data.nlobj != nothing
#             return true
#         end
#     end
#     return false
# end

#COPY OBJECTIVE FUNCTIONS
function _copy_objective(node::OptiNode,ref_map::AggregateMap)
    return _copy_objective(JuMP.objective_function(node),ref_map)
end

function _copy_objective(func::Union{JuMP.GenericAffExpr,JuMP.GenericQuadExpr}, ref_map::AggregateMap)
    new_func = _copy_constraint_func(func,ref_map)
    return new_func
end

function _copy_objective(func::JuMP.VariableRef, ref_map::AggregateMap)
    new_func = ref_map[func]
    return new_func
end

function _to_expression(func::JuMP.VariableRef)
    expr = :(0)
    expr = Expr(:call,:+,expr,:($(index(func))))
    return expr
end

function _to_expression(func::JuMP.GenericAffExpr)
    expr = :(0)
    for (term,coeff) in func.terms
        t_expr = Expr(:call,:*,:($coeff),:($(term.index)))
        expr = Expr(:call,:+,expr,t_expr)
    end
    expr = Expr(:call,:+,expr,:($(func.constant)))
    return expr
end

function _to_expression(func::JuMP.GenericQuadExpr)
    expr = :(0)
    for (term,coeff) in func.terms
        t_expr = :($coeff)
        t_expr = Expr(:call,:*,t_expr,:($(term.a.index)))
        t_expr = Expr(:call,:*,t_expr,:($(term.b.index)))
        expr = Expr(:call,:+,expr,t_expr)
    end
    aff_expr = _to_expression(func.aff)
    expr = Expr(:call,:+,expr,aff_expr)
    return expr
end

function _copy_nl_objective(d::JuMP.NLPEvaluator, reference_map::AggregateMap)
    if d.model.nlp_data.nlobj == nothing
        new_obj = _to_expression(JuMP.objective_function(d.model))
    else
        new_obj = MOI.objective_expr(d)
    end
        _splice_nonlinear_variables!(new_obj,getnode(d.model),reference_map)
        JuMP.objective_sense(d.model) == MOI.MAX_SENSE ? sense = -1 : sense = 1
        new_obj = Expr(:call,:*,:($sense),new_obj)
    return new_obj
end

#splice variables into a constraint expression
function _splice_nonlinear_variables!(expr::Expr, node::OptiNode, reference_map::AggregateMap)
    for i = 1:length(expr.args)
        if typeof(expr.args[i]) == Expr
            if expr.args[i].head != :ref #call _splice_nonlinear_variables! on the expression until it's a :ref. i.e. :(x[index])
                _splice_nonlinear_variables!(expr.args[i],node,reference_map)
            else  #it is a variable
                var_index = expr.args[i].args[2]     #this is the actual MOI index (e.g. x[1], x[2]) in the node model
                new_var = :($(reference_map.varmap[JuMP.VariableRef(node.model,var_index)]))
                expr.args[i] = new_var               #replace :(x[index]) with a :(JuMP.Variable)
            end
        end
    end
end

# COPY CONSTRAINT FUNCTIONS
function _copy_constraint_func(func::JuMP.GenericAffExpr,ref_map::AggregateMap)
    terms = func.terms
    new_terms = OrderedDict([(ref_map[var_ref],coeff) for (var_ref,coeff) in terms])
    new_func = JuMP.GenericAffExpr{Float64,JuMP.VariableRef}()
    new_func.terms = new_terms
    new_func.constant = func.constant
    return new_func
end

# function _copy_constraint_func(func::JuMP.GenericAffExpr,var_map::Dict{JuMP.VariableRef,JuMP.VariableRef})
#     terms = func.terms
#     new_terms = OrderedDict([(var_map[var_ref],coeff) for (var_ref,coeff) in terms])
#     new_func = JuMP.GenericAffExpr{Float64,JuMP.VariableRef}()
#     new_func.terms = new_terms
#     new_func.constant = func.constant
#     return new_func
# end

function _copy_constraint_func(func::JuMP.GenericQuadExpr,ref_map::AggregateMap)
    new_aff = _copy_constraint_func(func.aff,ref_map)
    new_terms = OrderedDict([(JuMP.UnorderedPair(ref_map[pair.a],ref_map[pair.b]),coeff) for (pair,coeff) in func.terms])
    new_func = JuMP.GenericQuadExpr{Float64,JuMP.VariableRef}()
    new_func.terms = new_terms
    new_func.aff = new_aff
    return new_func
end

function _copy_constraint_func(func::JuMP.VariableRef,ref_map::AggregateMap)
    new_func = ref_map[func]
    return new_func
end

function _copy_constraint(constraint::JuMP.ScalarConstraint,ref_map::AggregateMap)
    new_func = _copy_constraint_func(constraint.func,ref_map)
    new_con = JuMP.ScalarConstraint(new_func,constraint.set)
    return new_con
end

function _copy_constraint(constraint::JuMP.VectorConstraint,ref_map::AggregateMap)
    new_funcs = [_copy_constraint_func(func,ref_map) for func in constraint.func]
    new_con = JuMP.VectorConstraint(new_funcs,constraint.set,constraint.shape)
    return new_con
end

function _copy_constraint(constraint::LinkConstraint,ref_map::AggregateMap)
    new_func = _copy_constraint_func(constraint.func,ref_map)
    new_con = JuMP.ScalarConstraint(new_func,constraint.set)
    return new_con
end

# function _copy_constraint(constraint::LinkConstraint,var_map::Dict{JuMP.VariableRef,JuMP.VariableRef})
#     new_func = _copy_constraint_func(constraint.func,var_map)
#     new_con = JuMP.ScalarConstraint(new_func,constraint.set)
#     return new_con
# end

function _copy_node(node::OptiNode)
    new_node = OptiNode()
    reference_map = AggregateMap()
    temp_graph = OptiGraph()
    add_node!(temp_graph,node)
    new_node,reference_map = aggregate(temp_graph)
    return new_node,reference_map
end

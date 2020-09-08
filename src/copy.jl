#Check for nonlinear objective
function _has_nonlinear_obj(m::JuMP.Model)
    if m.nlp_data != nothing
        if m.nlp_data.nlobj != nothing
            return true
        end
    end
    return false
end

#COPY OBJECTIVE FUNCTIONS
function _copy_objective(m::JuMP.Model,ref_map::CombinedMap)
    return _copy_objective(JuMP.objective_function(m),ref_map)
end

function _copy_objective(func::Union{JuMP.GenericAffExpr,JuMP.GenericQuadExpr},ref_map::CombinedMap)
    new_func = _copy_constraint_func(func,ref_map)
    return new_func
end

function _copy_objective(func::JuMP.VariableRef,ref_map::CombinedMap)
    new_func = ref_map[func]
    return new_func
end

function _copy_nl_objective(d::JuMP.NLPEvaluator,reference_map::CombinedMap)#variablemap::Dict{Int,VariableRef})
    new_obj = MOI.objective_expr(d)
    _splice_nonlinear_variables!(new_obj,d.m,reference_map)
    JuMP.objective_sense(d.m) == MOI.OptimizationSense(0) ? sense = 1 : sense = -1
    new_obj = Expr(:call,:*,:($sense),new_obj)
    return new_obj
end

#splice variables into a constraint expression
function _splice_nonlinear_variables!(expr::Expr,model::JuMP.Model,reference_map::CombinedMap)  #var_map needs to map the node_model index to the new model variable
    for i = 1:length(expr.args)
        if typeof(expr.args[i]) == Expr
            if expr.args[i].head != :ref             #keep calling _splice_nonlinear_variables! on the expression until it's a :ref. i.e. :(x[index])
                _splice_nonlinear_variables!(expr.args[i],model,reference_map)
            else  #it's a variable
                var_index = expr.args[i].args[2]     #this is the actual MOI index (e.g. x[1], x[2]) in the node model
                new_var = :($(reference_map.varmap[JuMP.VariableRef(model,var_index)]))
                expr.args[i] = new_var               #replace :(x[index]) with a :(JuMP.Variable)
            end
        end
    end
end

# COPY CONSTRAINT FUNCTIONS
function _copy_constraint_func(func::JuMP.GenericAffExpr,ref_map::CombinedMap)
    terms = func.terms
    new_terms = OrderedDict([(ref_map[var_ref],coeff) for (var_ref,coeff) in terms])
    new_func = JuMP.GenericAffExpr{Float64,JuMP.VariableRef}()
    new_func.terms = new_terms
    new_func.constant = func.constant
    return new_func
end

function _copy_constraint_func(func::JuMP.GenericAffExpr,var_map::Dict{JuMP.VariableRef,JuMP.VariableRef})
    terms = func.terms
    new_terms = OrderedDict([(var_map[var_ref],coeff) for (var_ref,coeff) in terms])
    new_func = JuMP.GenericAffExpr{Float64,JuMP.VariableRef}()
    new_func.terms = new_terms
    new_func.constant = func.constant
    return new_func
end

function _copy_constraint_func(func::JuMP.GenericQuadExpr,ref_map::CombinedMap)
    new_aff = _copy_constraint_func(func.aff,ref_map)
    new_terms = OrderedDict([(JuMP.UnorderedPair(ref_map[pair.a],ref_map[pair.b]),coeff) for (pair,coeff) in func.terms])
    new_func = JuMP.GenericQuadExpr{Float64,JuMP.VariableRef}()
    new_func.terms = new_terms
    new_func.aff = new_aff
    #new_func.constant = func.constant
    return new_func
end

function _copy_constraint_func(func::JuMP.VariableRef,ref_map::CombinedMap)
    new_func = ref_map[func]
    return new_func
end

function _copy_constraint(constraint::JuMP.ScalarConstraint,ref_map::CombinedMap)
    new_func = _copy_constraint_func(constraint.func,ref_map)
    new_con = JuMP.ScalarConstraint(new_func,constraint.set)
    return new_con
end

function _copy_constraint(constraint::JuMP.VectorConstraint,ref_map::CombinedMap)
    new_funcs = [_copy_constraint_func(func,ref_map) for func in constraint.func]
    new_con = JuMP.VectorConstraint(new_funcs,constraint.set,constraint.shape)
    return new_con
end

function _copy_constraint(constraint::LinkConstraint,ref_map::CombinedMap)
    new_func = _copy_constraint_func(constraint.func,ref_map)
    new_con = JuMP.ScalarConstraint(new_func,constraint.set)
    return new_con
end

function _copy_constraint(constraint::LinkConstraint,var_map::Dict{JuMP.VariableRef,JuMP.VariableRef})
    new_func = _copy_constraint_func(constraint.func,var_map)
    new_con = JuMP.ScalarConstraint(new_func,constraint.set)
    return new_con
end


#TODO
function copy(mg::OptiGraph)
    new_graph = OptiGraph()
    for node in getnodes(mg)
        new_node,ref_map = copy(node)   #creates new _models.  Use ref map to reference old graph variables
        add_node!(new_graph,new_node)
    end
    for optiedge in getedges(mg)
    end

    #TODO copy linkconstraints
end

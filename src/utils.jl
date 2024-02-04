### Utilities for querying variables used in constraints

function _extract_variables(func::NodeVariableRef)
    return [func]
end

function _extract_variables(ref::ConstraintRef)
    func = JuMP.jump_function(JuMP.constraint_object(ref))
    return _extract_variables(func)
end

function _extract_variables(func::JuMP.GenericAffExpr)
    return collect(keys(func.terms))
end

function _extract_variables(func::JuMP.GenericQuadExpr)
    quad_vars = vcat([[term[2];term[3]] for term in JuMP.quad_terms(func)]...)
    aff_vars = _extract_variables(func.aff)
    return union(quad_vars,aff_vars)
end

function _extract_variables(func::JuMP.GenericNonlinearExpr)
    vars = NodeVariableRef[]
    for i = 1:length(func.args)
        func_arg = func.args[i]
        println("func_arg: ", func_arg)
        println("func_arg_type ", typeof(func_arg))
        if func_arg isa Number
        	continue
        elseif typeof(func_arg) == NodeVariableRef
            push!(vars, func_arg)
        else
            append!(vars, _extract_variables(func_arg))
        end
    end
    println("extracted vars ", vars)
    return vars
end
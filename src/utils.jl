#Number of constraints in a JuMP model
function num_all_constraints(m::JuMP.Model)
    num_cons = 0
    for (func,set) in JuMP.list_of_constraint_types(m)
        if func != JuMP.VariableRef
            num_cons += JuMP.num_constraints(m,func,set)
        end
    end
    num_cons += JuMP.num_nl_constraints(m)
    return num_cons
end


#Constraint data for linear and quadratic constraints
mutable struct ConstraintData
    linear_le_constraints#::Vector{JuMP.ScalarConstraint{JuMP.GenericAffExpr{Float64,JuMP.VariableRef},MathOptInterface.LessThan{Float64}}}
    linear_ge_constraints#::Vector{JuMP.ScalarConstraint{JuMP.GenericAffExpr{Float64,JuMP.VariableRef},MathOptInterface.GreaterThan{Float64}}}
	linear_interval_constraints#::Vector{JuMP.ScalarConstraint{JuMP.GenericAffExpr{Float64,JuMP.VariableRef},MathOptInterface.Interval{Float64}}}
    linear_eq_constraints#::Vector{JuMP.ScalarConstraint{JuMP.GenericAffExpr{Float64,JuMP.VariableRef},MathOptInterface.EqualTo{Float64}}}
    quadratic_le_constraints#::Vector{JuMP.ScalarConstraint{JuMP.GenericQuadExpr{Float64,JuMP.VariableRef},MathOptInterface.LessThan{Float64}}}
    quadratic_ge_constraints#::Vector{JuMP.ScalarConstraint{JuMP.GenericQuadExpr{Float64,JuMP.VariableRef},MathOptInterface.GreaterThan{Float64}}}
	quadratic_interval_constraints#::Vector{JuMP.ScalarConstraint{JuMP.GenericQuadExpr{Float64,JuMP.VariableRef},MathOptInterface.Interval{Float64}}}
    quadratic_eq_constraints#::Vector{JuMP.ScalarConstraint{JuMP.GenericQuadExpr{Float64,JuMP.VariableRef},MathOptInterface.EqualTo{Float64}}}
	nonlinear_constraints#::Vector{JuMP._NonlinearConstraint}
end

ConstraintData() = ConstraintData([], [], [], [], [], [],[],[],[])

function get_constraint_data(m::JuMP.Model)
	con_data = ConstraintData()

	constraint_types = JuMP.list_of_constraint_types(m)

    for (func,set) in constraint_types
        if func == JuMP.VariableRef 	#This is a variable bound, not a PIPS-NLP constraint
			continue
		else
	        constraint_refs = JuMP.all_constraints(m, func, set)
	        for constraint_ref in constraint_refs
	            constraint = JuMP.constraint_object(constraint_ref)

				func_type = typeof(constraint.func)
				con_type = typeof(constraint.set)

				if func_type == JuMP.GenericAffExpr{Float64,JuMP.VariableRef}
					if con_type == MOI.LessThan{Float64}
						push!(con_data.linear_le_constraints,constraint)
					elseif con_type == MOI.GreaterThan{Float64}
						push!(con_data.linear_ge_constraints,constraint)
					elseif con_type == MOI.Interval{Float64}
						push!(con_data.linear_interval_constraints,constraint)
					elseif con_type == MOI.EqualTo{Float64}
						push!(con_data.linear_eq_constraints,constraint)
					end
				elseif func_type == JuMP.GenericQuadExpr{Float64,JuMP.VariableRef}
					if con_type == MOI.LessThan{Float64}
						push!(con_data.quadratic_le_constraints,constraint)
					elseif con_type == MOI.GreaterThan{Float64}
						push!(con_data.quadratic_ge_constraints,constraint)
					elseif con_type == MOI.Interval{Float64}
						push!(con_data.quadratic_interval_constraints,constraint)
					elseif con_type == MOI.EqualTo{Float64}
						push!(con_data.quadtratic_eq_constraints,constraint)
					end
	            else
	                error("Could not figure out constraint type for $(constraint_ref)")
	            end
	        end
        end
    end
	if m.nlp_data != nothing
		con_data.nonlinear_constraints = m.nlp_data.nlconstr
	end
	return con_data
end

linear_le_offset(constraints::ConstraintData) = 0
linear_ge_offset(constraints::ConstraintData) = length(constraints.linear_le_constraints)
linear_interval_offset(constraints::ConstraintData) = linear_ge_offset(constraints) + length(constraints.linear_ge_constraints)
linear_eq_offset(constraints::ConstraintData) = linear_interval_offset(constraints) + length(constraints.linear_interval_constraints)
quadratic_le_offset(constraints::ConstraintData) = linear_eq_offset(constraints) + length(constraints.linear_eq_constraints)
quadratic_ge_offset(constraints::ConstraintData) = quadratic_le_offset(constraints) + length(constraints.quadratic_le_constraints)
quadratic_interval_offset(constraints::ConstraintData) =  quadratic_ge_offset(constraints) + length(constraints.quadratic_ge_constraints)
quadratic_eq_offset(constraints::ConstraintData) = quadratic_interval_offset(constraints) + length(constraints.quadratic_interval_constraints)
nlp_constraint_offset(constraints::ConstraintData) = quadratic_eq_offset(constraints) + length(constraints.quadratic_eq_constraints)



#####################################
# OBJECTIVE GRADIENT EVALUATION
#####################################
function has_nl_objective(m::JuMP.Model)
	if m.nlp_data == nothing
		return false
	elseif m.nlp_data.nlobj != nothing
		return true
	else
		return false
	end
end

function fill_gradient!(grad, x, var::JuMP.VariableRef)
    fill!(grad, 0.0)
    grad[var.index.value] = 1.0
	return
end

function fill_gradient!(grad, x, aff::JuMP.GenericAffExpr{Float64,JuMP.VariableRef})
    fill!(grad, 0.0)
	for	(var,coeff) in aff.terms
        grad[var.index.value] += coeff
    end
	return
end

function fill_gradient!(grad, x, quad::JuMP.GenericQuadExpr{Float64,JuMP.VariableRef})
    fill!(grad, 0.0)
    for	(var,coeff) in quad.aff.terms
        grad[var.index.value] += coeff
    end
    #for term in quad.quadratic_terms
	for (terms,coeff) in quad.terms
        row_idx = terms.a.index
        col_idx = terms.b.index
        if row_idx == col_idx
            grad[row_idx.value] += 2*coeff*x[row_idx.value]
        else
            grad[row_idx.value] += coeff*x[col_idx.value]
            grad[col_idx.value] += coeff*x[row_idx.value]
        end
    end
	return
end

function eval_objective_gradient(d::JuMP.NLPEvaluator, grad, x)
	m = d.m
    if has_nl_objective(m)
        MOI.eval_objective_gradient(d, grad, x)
    elseif JuMP.objective_function(m) !== nothing
        fill_gradient!(grad, x, JuMP.objective_function(m))
    else
        fill!(grad, 0.0)
    end
    return
end

###############################################################
# JACOBIAN STRUCTURE FOR VISUALIZING BLOCK STRUCTURE
###############################################################
function jump_jacobian_structure(m::JuMP.Model)
    d = JuMP.NLPEvaluator(m)
    return jump_jacobian_structure(d)
end

function append_to_jacobian_sparsity!(jacobian_sparsity, func::JuMP.GenericAffExpr{Float64,JuMP.VariableRef}, row)
	aff = func
    for term in keys(aff.terms)
        push!(jacobian_sparsity, (row, term.index.value))
    end
end

function append_to_jacobian_sparsity!(jacobian_sparsity, func::JuMP.GenericQuadExpr{Float64,JuMP.VariableRef}, row)
	quad = func
    for term in keys(quad.aff.terms)
        push!(jacobian_sparsity, (row, term.index.value))
    end
    for term in keys(quad.terms)
        row_idx = term.a.index
        col_idx = term.b.index
        if row_idx == col_idx
            push!(jacobian_sparsity, (row, row_idx.value))
        else
            push!(jacobian_sparsity, (row, row_idx.value))
            push!(jacobian_sparsity, (row, col_idx.value))
        end
    end
end

macro append_to_jacobian_sparsity(array_name)
    escrow = esc(:row)
    quote
        for constraint in $(esc(array_name))
			func = constraint.func
            append_to_jacobian_sparsity!($(esc(:jacobian_sparsity)), func, $escrow)
            $escrow += 1
        end
    end
end

function jump_jacobian_structure(d::JuMP.NLPEvaluator)

    num_nlp_constraints = JuMP.num_nl_constraints(d.m)
    if num_nlp_constraints > 0
		MOI.initialize(d,[:Grad,:Jac,:Hess])
        nlp_jacobian_sparsity = MOI.jacobian_structure(d)
    else
        nlp_jacobian_sparsity = []
    end

    jacobian_sparsity = Tuple{Int64,Int64}[]
    row = 1
	con_data = get_constraint_data(d.m)

    @append_to_jacobian_sparsity con_data.linear_le_constraints
    @append_to_jacobian_sparsity con_data.linear_ge_constraints
	@append_to_jacobian_sparsity con_data.linear_interval_constraints
    @append_to_jacobian_sparsity con_data.linear_eq_constraints
    @append_to_jacobian_sparsity con_data.quadratic_le_constraints
    @append_to_jacobian_sparsity con_data.quadratic_ge_constraints
	@append_to_jacobian_sparsity con_data.quadratic_interval_constraints
    @append_to_jacobian_sparsity con_data.quadratic_eq_constraints
    for (nlp_row, column) in nlp_jacobian_sparsity
        push!(jacobian_sparsity, (nlp_row + row - 1, column))
    end


    # I = [jacobian_sparsity[i][1] for i = 1:length(jacobian_sparsity)]
    # J = [jacobian_sparsity[i][2] for i = 1:length(jacobian_sparsity)]
    # V = ones(length(jacobian_sparsity))
    #
    # return sparse(I,J,V)
    return jacobian_sparsity
end




function get_link_constraint_data(graph::ModelGraph)
	con_data = ConstraintData()

    #link constraints can't be VariableRef
    for constraint in getlinkconstraints(graph)

		func_type = typeof(constraint.func)
		con_type = typeof(constraint.set)

		if func_type == JuMP.GenericAffExpr{Float64,JuMP.VariableRef}
			if con_type == MOI.LessThan{Float64}
				push!(con_data.linear_le_constraints,constraint)
			elseif con_type == MOI.GreaterThan{Float64}
				push!(con_data.linear_ge_constraints,constraint)
			elseif con_type == MOI.Interval{Float64}
				push!(con_data.linear_interval_constraints,constraint)
			elseif con_type == MOI.EqualTo{Float64}
				push!(con_data.linear_eq_constraints,constraint)
			end
		elseif func_type == JuMP.GenericQuadExpr{Float64,JuMP.VariableRef}
			if con_type == MOI.LessThan{Float64}
				push!(con_data.quadratic_le_constraints,constraint)
			elseif con_type == MOI.GreaterThan{Float64}
				push!(con_data.quadratic_ge_constraints,constraint)
			elseif con_type == MOI.Interval{Float64}
				push!(con_data.quadratic_interval_constraints,constraint)
			elseif con_type == MOI.EqualTo{Float64}
				push!(con_data.quadtratic_eq_constraints,constraint)
			end
        else
            error("Could not figure out constraint type for $(constraint_ref)")
        end
    end
	# if graph.nlp_data != nothing
	# 	con_data.nonlinear_constraints = m.nlp_data.nlconstr
	# end
	return con_data
end

function append_to_link_jacobian_sparsity!(jacobian_sparsity, func::JuMP.GenericAffExpr{Float64,JuMP.VariableRef}, row, var_map)
	aff = func
    for term in keys(aff.terms)
        push!(jacobian_sparsity, (row, var_map[term]))
    end
end

function append_to_link_jacobian_sparsity!(jacobian_sparsity, func::JuMP.GenericQuadExpr{Float64,JuMP.VariableRef}, row, var_map)
	quad = func
    for term in keys(quad.aff.terms)
        push!(jacobian_sparsity, (row, term.index.value))
    end
    for term in keys(quad.terms)
        row_idx = var_map[term]
        col_idx = var_map[term]
        if row_idx == col_idx
            push!(jacobian_sparsity, (row, row_idx.value))
        else
            push!(jacobian_sparsity, (row, row_idx.value))
            push!(jacobian_sparsity, (row, col_idx.value))
        end
    end
end

macro append_to_link_jacobian_sparsity(array_name)
    escrow = esc(:row)
    var_map = esc(:var_map)
    quote
        for constraint in $(esc(array_name))
			func = constraint.func
            append_to_link_jacobian_sparsity!($(esc(:jacobian_sparsity)), func, $escrow, $var_map)
            $escrow += 1
        end
    end
end


function link_jacobian_structure(graph::ModelGraph)
    jacobian_sparsity = Tuple{Int64,Int64}[]
    row = 1
	con_data = get_link_constraint_data(graph)

    #Map node variable indices to graph indices
    var_map = Dict()
    graph_index = 1
    for node in getnodes(graph)
        vars = JuMP.all_variables(node)
        for var in vars
            #index = var.index.value
            var_map[var] = graph_index
            graph_index += 1
        end
    end

    @append_to_link_jacobian_sparsity con_data.linear_le_constraints
    @append_to_link_jacobian_sparsity con_data.linear_ge_constraints
    @append_to_link_jacobian_sparsity con_data.linear_interval_constraints
    @append_to_link_jacobian_sparsity con_data.linear_eq_constraints
    @append_to_link_jacobian_sparsity con_data.quadratic_le_constraints
    @append_to_link_jacobian_sparsity con_data.quadratic_ge_constraints
    @append_to_link_jacobian_sparsity con_data.quadratic_interval_constraints
    @append_to_link_jacobian_sparsity con_data.quadratic_eq_constraints

    return jacobian_sparsity
end

#####################################
# JACOBIAN EVALUATION
#####################################
function fill_constraint_jacobian!(jac_values, start_offset, x, aff::JuMP.GenericAffExpr{Float64,JuMP.VariableRef})
    num_coefficients = length(aff.terms)
	i = 1
	for coeff in values(aff.terms) #ordered dictionary
        jac_values[start_offset+i] = coeff
		i += 1
    end
    return num_coefficients
end

function fill_constraint_jacobian!(jac_values, start_offset, x, quad::JuMP.GenericQuadExpr{Float64,JuMP.VariableRef})
	aff = quad.aff
    num_affine_coefficients = length(aff.terms)
	i = 1
	for coeff in values(aff.terms)
        jac_values[start_offset+i] = coeff #quad.affine_terms[i].coefficient
		i += 1
    end
    num_quadratic_coefficients = 0

	for (terms,coeff) in quad.terms
        row_idx = terms.a.index
        col_idx = terms.b.index
        if row_idx == col_idx
            jac_values[start_offset+num_affine_coefficients+num_quadratic_coefficients+1] = 2*coeff*x[row_idx.value]
            num_quadratic_coefficients += 1
        else
            # Note that the order matches the Jacobian sparsity pattern.
            jac_values[start_offset+num_affine_coefficients+num_quadratic_coefficients+1] = coeff*x[col_idx.value]
            jac_values[start_offset+num_affine_coefficients+num_quadratic_coefficients+2] = coeff*x[row_idx.value]
            num_quadratic_coefficients += 2
        end
    end
    return num_affine_coefficients + num_quadratic_coefficients
end

# Refers to local variables in eval_constraint_jacobian() below.
macro fill_constraint_jacobian(array_name)
    esc_offset = esc(:offset)
    quote
        for constraint in $(esc(array_name))
			func = constraint.func
            $esc_offset += fill_constraint_jacobian!($(esc(:jac_values)),$esc_offset, $(esc(:x)),func)
        end
    end
end

function eval_constraint_jacobian(d::JuMP.NLPEvaluator, jac_values, x)
    offset = 0
	m = d.m
	con_data = m.ext[:constraint_data]
    @fill_constraint_jacobian con_data.linear_le_constraints
    @fill_constraint_jacobian con_data.linear_ge_constraints
	@fill_constraint_jacobian con_data.linear_interval_constraints
    @fill_constraint_jacobian con_data.linear_eq_constraints
    @fill_constraint_jacobian con_data.quadratic_le_constraints
    @fill_constraint_jacobian con_data.quadratic_ge_constraints
	@fill_constraint_jacobian con_data.quadratic_interval_constraints
    @fill_constraint_jacobian con_data.quadratic_eq_constraints

    println("nonlinear now")
    nlp_values = view(jac_values, 1+offset:length(jac_values))
    MOI.eval_constraint_jacobian(d, nlp_values, x)
    return
end

#NOTE Code inspired by JuMP's NLPEvaluator and MadNLP.jl implementation
#OptiGraph NLP Evaluator.  Wraps Local JuMP NLP Evaluators.

#IDEA: evaluator could work in multiple modes.
#1: Same as JuMP, evaluates NLP part of model (currently supported).
#2  Treats the entire model as an NLP, evaluates linear and quadratic terms too (not yet supported).
mutable struct OptiGraphNLPEvaluator <: MOI.AbstractNLPEvaluator
    graph::OptiGraph
    optinodes::Vector{OptiNode}

    nlps::Union{Nothing,Vector{JuMP.NLPEvaluator}} #nlp evaluators for optinodes
    has_nlobj
    n       #num variables (columns)
    m       #num constraints (rows)
    #p       #num link constraints (rows)
    ninds   #variable indices for each node
    minds   #row indicies for each node
    #pinds   #link constraint indices
    nnzs_hess_inds
    nnzs_jac_inds
    #nnzs_link_jac_inds
    nnz_hess
    nnz_jac

    ###############################################################################
    #TODO someday: nonlinear optigraph objective and nonlinear linking constraints.  For now, we assume the objective is the summation across nodes (i.e. separable)
    # The general idea would need to replace MOI Variable Indices for each optinode when initializing the evaluator
    # We would have to handle non-seperable objective functions
    # objective::JuMP._FunctionStorage
    # constraints::Vector{JuMP._FunctionStorage}

    # timers
    eval_objective_timer::Float64
    eval_constraint_timer::Float64
    eval_objective_gradient_timer::Float64
    eval_constraint_jacobian_timer::Float64
    eval_hessian_lagrangian_timer::Float64
    function OptiGraphNLPEvaluator(graph::OptiGraph)
        d = new(graph)
        d.eval_objective_timer = 0
        d.eval_constraint_timer = 0
        d.eval_objective_gradient_timer = 0
        d.eval_constraint_jacobian_timer = 0
        d.eval_hessian_lagrangian_timer = 0
        return d
    end
end

#Initialize
function MOI.initialize(d::OptiGraphNLPEvaluator,requested_features::Vector{Symbol})
    graph = d.graph
    optinodes = all_nodes(graph)
    linkedges = all_edges(graph)

    d.optinodes = optinodes
    d.nlps = Vector{JuMP.NLPEvaluator}(undef,length(optinodes)) #Initialize each optinode with the requested features
    d.has_nlobj = false

    #@blas_safe_threads for k=1:length(optinodes)
    for k=1:length(optinodes)
        if optinodes[k].nlp_data == nothing
            # JuMP._init_NLP(optinodes[k].model)
            JuMP._init_NLP(optinodes[k])
        end
        d_node = JuMP.NLPEvaluator(optinodes[k].model)     #Initialize each optinode evaluator
        MOI.initialize(d_node,requested_features)
        d.nlps[k] = d_node
        if d_node.has_nlobj
            d.has_nlobj = true
        end
    end

    K = length(optinodes)

    #num variables in optigraph
    ns= [num_variables(optinode) for optinode in optinodes]
    n = sum(ns)
    ns_cumsum = cumsum(ns)

    #num constraints NOTE: Should this just be NL constraints? Depends on evaluator mode
    ms= [num_nl_constraints(optinode) for optinode in optinodes]
    m = sum(ms)
    ms_cumsum = cumsum(ms)

    #hessian nonzeros: This grabs quadratic terms if we have a nonlinear objective function on any node
    if d.has_nlobj
        #TODO: grab constraint too
        nnzs_hess = [_get_nnz_hess_quad(d.nlps[k]) for k = 1:K]
    else
        nnzs_hess = [_get_nnz_hess(d.nlps[k]) for k = 1:K]
    end

    #nnzs_hess = [_get_nnz_hess(d.nlps[k]) for k = 1:K]
    nnzs_hess_cumsum = cumsum(nnzs_hess)
    d.nnz_hess = sum(nnzs_hess)

    #jacobian nonzeros
    nnzs_jac = [_get_nnz_jac(d.nlps[k]) for k = 1:K]
    nnzs_jac_cumsum = cumsum(nnzs_jac)
    d.nnz_jac = sum(nnzs_jac)

    # link jacobian nonzeros (These wouldn't be returned in the JuMP NLP Evaluator)
    # nnzs_link_jac = [get_nnz_link_jac(linkedge) for linkedge in linkedges]
    # nnzs_link_jac_cumsum = cumsum(nnzs_link_jac)
    # nnz_link_jac = isempty(nnzs_link_jac) ? 0 : sum(nnzs_link_jac)

    #variable indices and constraint indices
    ninds = [(i==1 ? 0 : ns_cumsum[i-1])+1:ns_cumsum[i] for i=1:K]
    minds = [(i==1 ? 0 : ms_cumsum[i-1])+1:ms_cumsum[i] for i=1:K]

    #nonzero indices for hessian and jacobian
    nnzs_hess_inds = [(i==1 ? 0 : nnzs_hess_cumsum[i-1])+1:nnzs_hess_cumsum[i] for i=1:K]
    nnzs_jac_inds = [(i==1 ? 0 : nnzs_jac_cumsum[i-1])+1:nnzs_jac_cumsum[i] for i=1:K]

    # #num linkedges
    # Q = length(linkedges)
    # ps= [num_linkconstraints(optiedge) for optiedge in linkedges]
    # ps_cumsum =  cumsum(ps)
    # p = sum(ps)
    # pinds = [(i==1 ? m : m+ps_cumsum[i-1])+1:m+ps_cumsum[i] for i=1:Q]

    #link jacobian nonzero indices
    #nnzs_link_jac_inds = [(i==1 ? nnz_jac : nnz_jac+nnzs_link_jac_cumsum[i-1])+1: nnz_jac + nnzs_link_jac_cumsum[i] for i=1:Q]

    d.n = n
    d.m = m
    #d.p = p
    d.ninds = ninds
    d.minds = minds
    #d.pinds = pinds
    d.nnzs_hess_inds = nnzs_hess_inds
    d.nnzs_jac_inds = nnzs_jac_inds
    #d.nnzs_link_jac_inds = d.nnzs_link_jac_inds

end

_get_nnz_hess(obj::Union{JuMP.VariableRef,JuMP.GenericAffExpr}) = 0
_get_nnz_hess(obj::JuMP.GenericQuadExpr) = length(obj.terms)
_get_nnz_hess(d_node::JuMP.NLPEvaluator) = length(MOI.hessian_lagrangian_structure(d_node))
_get_nnz_jac(d_node::JuMP.NLPEvaluator) = length(MOI.jacobian_structure(d_node))

function _get_nnz_hess_quad(d_node::JuMP.NLPEvaluator)
    if d_node.has_nlobj
        return _get_nnz_hess(d_node)
    else
        return _get_nnz_hess(d_node) + _get_nnz_hess(objective_function(d_node.m))
    end
end

MOI.features_available(d::OptiGraphNLPEvaluator) = [:Grad,:Hess,:Jac]

#Objective Function
function MOI.eval_objective(d::OptiGraphNLPEvaluator, x)
    ninds = d.ninds
    optinodes = d.optinodes
    d.eval_objective_timer += @elapsed begin
        if d.has_nlobj #if any optinode has a nonlinear objective, we treat the optigraph as having a nonlinear objective
            obj = Threads.Atomic{Float64}(0.)
            #@blas_safe_threads for k=1:length(optinodes)
            for k = 1:length(d.nlps)
                if d.nlps[k].has_nlobj
                    Threads.atomic_add!(obj,MOI.eval_objective(d.nlps[k],view(x,ninds[k])))
                else
                    Threads.atomic_add!(obj,_eval_function(objective_function(optinodes[k]),view(x,ninds[k])))
                end
            end
        else
            error("No nonlinear objective.")
        end
    end
    return obj.value
end

function _eval_function(var::JuMP.VariableRef, x)
    return x[var.index.value]
end

function _eval_function(aff::JuMP.GenericAffExpr,x)
    function_value = aff.constant
    for (var,coef) in aff.terms
        function_value += coef*x[var.index.value]
    end
    return function_value
end

function _eval_function(quad::JuMP.GenericQuadExpr, x)
    function_value = quad.aff.constant
    for (var,coef) in quad.aff.terms
        function_value += coef*x[var.index.value]
    end
    for (terms,coef) in quad.terms
        row_idx = terms.a.index
        col_idx = terms.b.index
		function_value += coef*x[row_idx.value]*x[col_idx.value]
    end
    return function_value
end

function MOI.eval_objective_gradient(d::OptiGraphNLPEvaluator,grad,x)
    ninds = d.ninds
    d.eval_objective_gradient_timer += @elapsed begin
        if d.has_nlobj
            fill!(grad, 0.0)
            # @blas_safe_threads for k=1:length(modelnodes)
            for k = 1:length(d.nlps)
                if d.nlps[k].has_nlobj
                    MOI.eval_objective_gradient(d.nlps[k],view(grad,ninds[k]),view(x,ninds[k]))
                else
                    _fill_gradient!(objective_function(d.nlps[k].m),view(grad,ninds[k]),view(x,ninds[k]))
                end
            end
        else
            error("No nonlinear objective.")
        end
    end
    return
end

function _fill_gradient!(var::JuMP.VariableRef, grad, x)
    grad[var.index.value] = 1.0
	return
end

function _fill_gradient!( aff::JuMP.GenericAffExpr,grad, x)
	for	(var,coef) in aff.terms
        grad[var.index.value] += coef
    end
	return
end

function _fill_gradient!(quad::JuMP.GenericQuadExpr,grad, x)
    for	(var,coef) in quad.aff.terms
        grad[var.index.value] += coef
    end
	for (terms,coef) in quad.terms
        row_idx = terms.a.index
        col_idx = terms.b.index
        if row_idx == col_idx
            grad[row_idx.value] += 2*coef*x[row_idx.value]
        else
            grad[row_idx.value] += coef*x[col_idx.value]
            grad[col_idx.value] += coef*x[row_idx.value]
        end
    end
	return
end

function MOI.hessian_lagrangian_structure(d::OptiGraphNLPEvaluator)
    nnzs_hess_inds = d.nnzs_hess_inds
    nnz_hess = d.nnz_hess

    I = Vector{Int64}(undef,d.nnz_hess)
    J = Vector{Int64}(undef,d.nnz_hess)

    # @blas_safe_threads for k=1:length(optinodes)
    for k=1:length(d.nlps)
        isempty(nnzs_hess_inds[k]) && continue
        offset = d.ninds[k][1]-1
        II = view(I,nnzs_hess_inds[k])
        JJ = view(J,nnzs_hess_inds[k])
        if d.has_nlobj #if the optigraph has a nonlinear objective on any node, we need to treat quadratic objectives as nonlinear
            _hessian_lagrangian_structure_quad(d.nlps[k],II,JJ)
        else #just run the normal JuMP function
            _hessian_lagrangian_structure(d.nlps[k],II,JJ)
        end
        II.+= offset
        JJ.+= offset
    end
    hessian_sparsity = collect(zip(I,J)) # return Tuple{Int64,Int64}[]
    return hessian_sparsity
end

#Hessian Lagrangian structure without quadratic objective terms included
function _hessian_lagrangian_structure(d::JuMP.NLPEvaluator,I,J)
    cnt = 0
    for (row,col) in MOI.hessian_lagrangian_structure(d)
        I[1+cnt]=row
        J[1+cnt]=col
        cnt+=1
    end
end

#Hessian Lagrangian structure with quadratic objective terms included
function _hessian_lagrangian_structure_quad(d::JuMP.NLPEvaluator,I,J)
    if !(d.has_nlobj)
        obj = objective_function(d.m)
        offset = append_to_hessian_sparsity!(I,J,obj,1) + 1
    else
        offset = 1
    end
    cnt = 0
    for (row,col) in MOI.hessian_lagrangian_structure(d)
        I[offset+cnt]=row
        J[offset+cnt]=col
        cnt+=1
    end
end

function append_to_hessian_sparsity!(I,J,quad::JuMP.GenericQuadExpr,offset)
    cnt = 0
    for term in keys(quad.terms)
        I[offset+cnt]=term.a.index.value
        J[offset+cnt]=term.b.index.value
        cnt+=1
    end
    return cnt
end
append_to_hessian_sparsity!(I,J,::Union{JuMP.VariableRef,JuMP.GenericAffExpr},offset) = 0

function MOI.jacobian_structure(d::OptiGraphNLPEvaluator)
    nnzs_jac_inds = d.nnzs_jac_inds
    I = Vector{Int64}(undef,d.nnz_jac)
    J = Vector{Int64}(undef,d.nnz_jac)
    #@blas_safe_threads for k=1:length(modelnodes)
    for k=1:length(d.nlps)
        isempty(nnzs_jac_inds[k]) && continue
        offset_i = d.minds[k][1]-1
        offset_j = d.ninds[k][1]-1
        II = view(I,nnzs_jac_inds[k])
        JJ = view(J,nnzs_jac_inds[k])
        _jacobian_structure(d.nlps[k],II,JJ)
        II.+= offset_i
        JJ.+= offset_j
    end
    jacobian_sparsity = collect(zip(I,J)) # return Tuple{Int64,Int64}[]
    return jacobian_sparsity
end

function _jacobian_structure(d::JuMP.NLPEvaluator,I,J)
    cnt = 0
    for (nlp_row, nlp_col) in MOI.jacobian_structure(d)
        I[1+cnt] = nlp_row
        J[1+cnt] = nlp_col
        cnt+=1
    end
end

function MOI.eval_constraint(d::OptiGraphNLPEvaluator,c::AbstractArray,x::AbstractArray)
    # @blas_safe_threads for k=1:length(modelnodes)
    for k=1:length(d.nlps)
        MOI.eval_constraint(d.nlps[k],view(c,d.minds[k]),view(x,d.ninds[k]))
    end
end

######################################
function MOI.eval_hessian_lagrangian(d::OptiGraphNLPEvaluator,hess::AbstractArray,x::AbstractArray,sigma::Float64,mu::AbstractArray)
    lk = Threads.ReentrantLock()
    Threads.lock(lk)
    for k=1:length(d.nlps)
        isempty(d.nnzs_hess_inds[k]) && continue
        if d.has_nlobj
            _eval_hessian_lagrangian_quad(d.nlps[k],view(hess,d.nnzs_hess_inds[k]),view(x,d.ninds[k]),sigma,view(mu,d.minds[k]))
        else
            _eval_hessian_lagrangian(d.nlps[k],view(hess,d.nnzs_hess_inds[k]),view(x,d.ninds[k]),sigma,view(mu,d.minds[k]))
        end
    end
    Threads.unlock(lk)
end

_eval_hessian_lagrangian(d::JuMP.NLPEvaluator,hess,x,sigma,mu) = MOI.eval_hessian_lagrangian(d,hess,x,sigma,mu)

function _eval_hessian_lagrangian_quad(d::JuMP.NLPEvaluator,hess,x,sigma,mu)
    offset = fill_hessian_lagrangian!(hess, 0, sigma, JuMP.objective_function(d.m))
    nlp_values = view(hess, 1 + offset : length(hess))
    MOI.eval_hessian_lagrangian(d, nlp_values, x, sigma, mu)
end

function fill_hessian_lagrangian!(hess, start_offset, sigma,::Union{JuMP.VariableRef,JuMP.GenericAffExpr{Float64,JuMP.VariableRef},Nothing})
    return 0
end

function fill_hessian_lagrangian!(hess, start_offset, sigma, quad::JuMP.GenericQuadExpr{Float64,JuMP.VariableRef})
	i = 1
	for (terms,coeff) in quad.terms
		row_idx = terms.a.index
		col_idx = terms.b.index
		if row_idx == col_idx
			hess[start_offset + i] = 2*sigma*coeff
		else
			hess[start_offset + i] = sigma*coeff
		end
		i += 1
	end
    return length(quad.terms)
end

function MOI.eval_constraint_jacobian(d::OptiGraphNLPEvaluator,jac,x)
    # @blas_safe_threads for k=1:length(modelnodes)
    for k=1:length(d.nlps)
        MOI.eval_constraint_jacobian(d.nlps[k],view(jac,d.nnzs_jac_inds[k]),view(x,d.ninds[k]))
    end
end

#TODO:
MOI.objective_expr(d::OptiGraphNLPEvaluator) = 0
MOI.constraint_expr(d::OptiGraphNLPEvaluator) = 0

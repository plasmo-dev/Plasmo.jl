#NOTE Code inspired by JuMP NLPEvaluator and MadNLP.jl NLP implementation
#OptiGraph NLP Evaluator.  Wraps Local JuMP NLP Evaluators.

#IDEA: evaluator could work in multiple modes.
#1: Same as JuMP, evaluates NLP part of model.
#2 Treats the entire model as an NLP, evaluates linear and quadratic terms too.
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
                    Threads.atomic_add!(obj,_eval_function(objective_function(optinodes[k]),view(x,ninds[k]))) #,x_index_map))
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
###########################################################################
##########################################################################

# function jacobian_structure(linkedge::OptiEdge,I,J,ninds,x_index_map,g_index_map)
#     offset=1
#     for linkcon in getlinkconstraints(linkedge)
#         offset += jacobian_structure(linkcon,I,J,ninds,x_index_map,g_index_map,offset)
#     end
# end
#
# function jacobian_structure(linkcon,I,J,ninds,x_index_map,g_index_map,offset)
#     cnt = 0
#     for var in get_vars(linkcon)
#         I[offset+cnt] = g_index_map[linkcon]
#         J[offset+cnt] = x_index_map[var]
#         cnt += 1
#     end
#     return cnt
# end
#
# function jacobian_structure(graph::OptiGraph,I,J,ninds,minds,pinds,
#     nnzs_jac_inds,nnzs_link_jac_inds,
#     x_index_map,g_index_map,modelnodes,linkedges)
#
#     @blas_safe_threads for k=1:length(modelnodes)
#         isempty(nnzs_jac_inds[k]) && continue
#         offset_i = minds[k][1]-1
#         offset_j = ninds[k][1]-1
#         II = view(I,nnzs_jac_inds[k])
#         JJ = view(J,nnzs_jac_inds[k])
#         jacobian_structure(
#             moi_optimizer(modelnodes[k]),II,JJ)
#         II.+= offset_i
#         JJ.+= offset_j
#     end
#
#     @blas_safe_threads for q=1:length(linkedges)
#         isempty(nnzs_link_jac_inds[q]) && continue
#         II = view(I,nnzs_link_jac_inds[q])
#         JJ = view(J,nnzs_link_jac_inds[q])
#         jacobian_structure(
#             linkedges[q],II,JJ,ninds,x_index_map,g_index_map)
#     end
# end
#
#
# function eval_constraint(linkedge::OptiEdge,c,x,ninds,x_index_map)
#     cnt = 1
#     for linkcon in getlinkconstraints(linkedge)
#         c[cnt] = eval_function(get_func(linkcon),x,ninds,x_index_map)
#         cnt += 1
#     end
# end
# get_func(linkcon) = linkcon.func
# function eval_constraint(graph::OptiGraph,c,x,ninds,minds,pinds,x_index_map,modelnodes,linkedges)
#     @blas_safe_threads for k=1:length(modelnodes)
#         eval_constraint(moi_optimizer(modelnodes[k]),view(c,minds[k]),view(x,ninds[k]))
#     end
#     @blas_safe_threads for q=1:length(linkedges)
#         eval_constraint(linkedges[q],view(c,pinds[q]),x,ninds,x_index_map)
#     end
# end
#
# function eval_hessian_lagrangian(graph::OptiGraph,hess,x,sig,l,
#                                  ninds,minds,nnzs_hess_inds,modelnodes)
#     @blas_safe_threads for k=1:length(modelnodes)
#         isempty(nnzs_hess_inds) && continue
#         eval_hessian_lagrangian(moi_optimizer(modelnodes[k]),
#                                 view(hess,nnzs_hess_inds[k]),view(x,ninds[k]),sig,
#                                 view(l,minds[k]))
#     end
# end
#
# function eval_constraint_jacobian(linkedge::OptiEdge,jac,x)
#     offset=0
#     for linkcon in getlinkconstraints(linkedge)
#         offset+=eval_constraint_jacobian(linkcon,jac,offset)
#     end
# end
# function eval_constraint_jacobian(linkcon,jac,offset)
#     cnt = 0
#     for coef in get_coeffs(linkcon)
#         cnt += 1
#         jac[offset+cnt] = coef
#     end
#     return cnt
# end
# get_vars(linkcon) = keys(linkcon.func.terms)
# get_coeffs(linkcon) = values(linkcon.func.terms)
#
# function eval_constraint_jacobian(graph::OptiGraph,jac,x,
#                                   ninds,minds,nnzs_jac_inds,nnzs_link_jac_inds,modelnodes,linkedges)
#     @blas_safe_threads for k=1:length(modelnodes)
#         eval_constraint_jacobian(
#             moi_optimizer(modelnodes[k]),view(jac,nnzs_jac_inds[k]),view(x,ninds[k]))
#     end
#     @blas_safe_threads for q=1:length(linkedges)
#         eval_constraint_jacobian(linkedges[q],view(jac,nnzs_link_jac_inds[q]),x)
#     end
# end
# get_nnz_link_jac(linkedge::OptiEdge) = sum(length(linkcon.func.terms) for (ind,linkcon) in linkedge.linkconstraints)

##########################################################################

#Check for empty optinodes
# for optinode in optinodes
#     num_variables(optinode) == 0 && error("Detected optinode with 0 variables.  The Plasmo NLP interface does not yet support optinodes with zero variables.")
# end

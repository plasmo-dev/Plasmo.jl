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

    #TODO someday: nonlinear optigraph objective and nonlinear linking constraints.  For now, we assume the objective is either the summation across nodes
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

    #num constraints NOTE: Should this just be NL constraints?
    ms= [num_nl_constraints(optinode) for optinode in optinodes]
    m = sum(ms)
    ms_cumsum = cumsum(ms)

    #hessian nonzeros
    nnzs_hess = [_get_nnz_hess(d.nlps[k]) for k = 1:K]
    nnzs_hess_cumsum = cumsum(nnzs_hess)
    nnz_hess = sum(nnzs_hess)

    #jacobian nonzeros
    nnzs_jac = [_get_nnz_jac(d.nlps[k]) for k = 1:K]
    nnzs_jac_cumsum = cumsum(nnzs_jac)
    nnz_jac = sum(nnzs_jac)

    #link jacobian nonzeros (These wouldn't be returned in the JuMP NLP Evaluator)
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

_get_nnz_hess(d_node::JuMP.NLPEvaluator) = length(MOI.hessian_lagrangian_structure(d_node))
_get_nnz_jac(d_node::JuMP.NLPEvaluator) = length(MOI.jacobian_structure(d_node))

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

function _eval_function(aff::GenericAffExpr,x)
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


###########################################################################
# function MOI.eval_objective_gradient(d::OptiGraphNLPEvaluator,g,x)
#     ninds = d.inds
#     optinodes = d.optinodes
#
#     d.eval_objective_gradient_timer += @elapsed begin
#     # if d.has_nlobj
#     #     fill!(g, 0.0)
#
#     # @blas_safe_threads for k=1:length(modelnodes)
#     for k=1:length(optinodes)
#         MOI.eval_objective_gradient(d.nlps[k],view(g,ninds[k]),view(x,ninds[k]))
#     end
# end

#
# function MOI.eval_objective_gradient(d::NLPEvaluator, g, x)
#     d.eval_objective_gradient_timer += @elapsed begin
#         if d.last_x != x
#             _forward_eval_all(d, x)
#             _reverse_eval_all(d, x)
#         end
#         if d.has_nlobj
#             fill!(g, 0.0)
#             ex = d.objective
#             subexpr_reverse_values = d.subexpression_reverse_values
#             subexpr_reverse_values[ex.dependent_subexpressions] .= 0.0
#             reverse_extract(
#                 g,
#                 ex.reverse_storage,
#                 ex.nd,
#                 ex.adj,
#                 subexpr_reverse_values,
#                 1.0,
#             )
#             for i in length(ex.dependent_subexpressions):-1:1
#                 k = ex.dependent_subexpressions[i]
#                 subexpr = d.subexpressions[k]
#                 reverse_extract(
#                     g,
#                     subexpr.reverse_storage,
#                     subexpr.nd,
#                     subexpr.adj,
#                     subexpr_reverse_values,
#                     subexpr_reverse_values[k],
#                 )
#             end
#         else
#             error("No nonlinear objective.")
#         end
#     end
#     return
# end
#
# # function eval_objective_gradient(graph::OptiGraph,f,x,ninds,modelnodes)
# #     @blas_safe_threads for k=1:length(modelnodes)
# #         eval_objective_gradient(moi_optimizer(modelnodes[k]),view(f,ninds[k]),view(x,ninds[k]))
# #     end
# # end
#
#
# function hessian_lagrangian_structure(graph::OptiGraph,I,J,ninds,nnzs_hess_inds,optinodes)
#     @blas_safe_threads for k=1:length(optinodes)
#         isempty(nnzs_hess_inds[k]) && continue
#         offset = ninds[k][1]-1
#         II = view(I,nnzs_hess_inds[k])
#         JJ = view(J,nnzs_hess_inds[k])
#         hessian_lagrangian_structure(moi_optimizer(optinodes[k]),II,JJ)
#         II.+= offset
#         JJ.+= offset
#     end
# end
#
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

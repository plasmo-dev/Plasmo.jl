#Code re-used from MadNLP.jl

mutable struct OptiGraphNLPEvaluator
    obj::Function
    obj_grad!::Function

    con!::Function
    con_jac!::Function
    lag_hess!::Function

    hess_sparsity!::Function
    jac_sparsity!::Function

    status::Status
end

function hessian_lagrangian_structure(graph::OptiGraph,I,J,ninds,nnzs_hess_inds,optinodes)
    @blas_safe_threads for k=1:length(optinodes)
        isempty(nnzs_hess_inds[k]) && continue
        offset = ninds[k][1]-1
        II = view(I,nnzs_hess_inds[k])
        JJ = view(J,nnzs_hess_inds[k])
        hessian_lagrangian_structure(moi_optimizer(optinodes[k]),II,JJ)
        II.+= offset
        JJ.+= offset
    end
end

function jacobian_structure(linkedge::OptiEdge,I,J,ninds,x_index_map,g_index_map)
    offset=1
    for linkcon in getlinkconstraints(linkedge)
        offset += jacobian_structure(linkcon,I,J,ninds,x_index_map,g_index_map,offset)
    end
end

function jacobian_structure(linkcon,I,J,ninds,x_index_map,g_index_map,offset)
    cnt = 0
    for var in get_vars(linkcon)
        I[offset+cnt] = g_index_map[linkcon]
        J[offset+cnt] = x_index_map[var]
        cnt += 1
    end
    return cnt
end

function jacobian_structure(
    graph::OptiGraph,I,J,ninds,minds,pinds,nnzs_jac_inds,nnzs_link_jac_inds,
    x_index_map,g_index_map,modelnodes,linkedges)

    @blas_safe_threads for k=1:length(modelnodes)
        isempty(nnzs_jac_inds[k]) && continue
        offset_i = minds[k][1]-1
        offset_j = ninds[k][1]-1
        II = view(I,nnzs_jac_inds[k])
        JJ = view(J,nnzs_jac_inds[k])
        jacobian_structure(
            moi_optimizer(modelnodes[k]),II,JJ)
        II.+= offset_i
        JJ.+= offset_j
    end

    @blas_safe_threads for q=1:length(linkedges)
        isempty(nnzs_link_jac_inds[q]) && continue
        II = view(I,nnzs_link_jac_inds[q])
        JJ = view(J,nnzs_link_jac_inds[q])
        jacobian_structure(
            linkedges[q],II,JJ,ninds,x_index_map,g_index_map)
    end
end
function eval_objective(graph::OptiGraph,x,ninds,x_index_map,modelnodes)
    obj = Threads.Atomic{Float64}(0.)
    @blas_safe_threads for k=1:length(modelnodes)
         Threads.atomic_add!(obj,eval_objective(
             moi_optimizer(modelnodes[k]),view(x,ninds[k])))
    end
    return obj.value + eval_function(graph.objective_function,x,ninds,x_index_map)
end
function eval_objective_gradient(graph::OptiGraph,f,x,ninds,modelnodes)
    @blas_safe_threads for k=1:length(modelnodes)
        eval_objective_gradient(moi_optimizer(modelnodes[k]),view(f,ninds[k]),view(x,ninds[k]))
    end
end

function eval_function(aff::GenericAffExpr,x,ninds,x_index_map)
    function_value = aff.constant
    for (var,coef) in aff.terms
        function_value += coef*x[x_index_map[var]]
    end
    return function_value
end
function eval_constraint(linkedge::OptiEdge,c,x,ninds,x_index_map)
    cnt = 1
    for linkcon in getlinkconstraints(linkedge)
        c[cnt] = eval_function(get_func(linkcon),x,ninds,x_index_map)
        cnt += 1
    end
end
get_func(linkcon) = linkcon.func
function eval_constraint(graph::OptiGraph,c,x,ninds,minds,pinds,x_index_map,modelnodes,linkedges)
    @blas_safe_threads for k=1:length(modelnodes)
        eval_constraint(moi_optimizer(modelnodes[k]),view(c,minds[k]),view(x,ninds[k]))
    end
    @blas_safe_threads for q=1:length(linkedges)
        eval_constraint(linkedges[q],view(c,pinds[q]),x,ninds,x_index_map)
    end
end

function eval_hessian_lagrangian(graph::OptiGraph,hess,x,sig,l,
                                 ninds,minds,nnzs_hess_inds,modelnodes)
    @blas_safe_threads for k=1:length(modelnodes)
        isempty(nnzs_hess_inds) && continue
        eval_hessian_lagrangian(moi_optimizer(modelnodes[k]),
                                view(hess,nnzs_hess_inds[k]),view(x,ninds[k]),sig,
                                view(l,minds[k]))
    end
end

function eval_constraint_jacobian(linkedge::OptiEdge,jac,x)
    offset=0
    for linkcon in getlinkconstraints(linkedge)
        offset+=eval_constraint_jacobian(linkcon,jac,offset)
    end
end
function eval_constraint_jacobian(linkcon,jac,offset)
    cnt = 0
    for coef in get_coeffs(linkcon)
        cnt += 1
        jac[offset+cnt] = coef
    end
    return cnt
end
get_vars(linkcon) = keys(linkcon.func.terms)
get_coeffs(linkcon) = values(linkcon.func.terms)

function eval_constraint_jacobian(graph::OptiGraph,jac,x,
                                  ninds,minds,nnzs_jac_inds,nnzs_link_jac_inds,modelnodes,linkedges)
    @blas_safe_threads for k=1:length(modelnodes)
        eval_constraint_jacobian(
            moi_optimizer(modelnodes[k]),view(jac,nnzs_jac_inds[k]),view(x,ninds[k]))
    end
    @blas_safe_threads for q=1:length(linkedges)
        eval_constraint_jacobian(linkedges[q],view(jac,nnzs_link_jac_inds[q]),x)
    end
end
get_nnz_link_jac(linkedge::OptiEdge) = sum(
    length(linkcon.func.terms) for (ind,linkcon) in linkedge.linkconstraints)

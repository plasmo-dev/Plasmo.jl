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

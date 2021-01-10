#NOTE Code re-used from MadNLP.jl

#NLP Data for nonliner objective function and (someday) nonlinear link constraints
function JuMP._init_NLP(graph::OptiGraph)
    if graph.nlp_data === nothing
        graph.nlp_data = JuMP._NLPData()
    end
end

#OptiGraph NLP Evaluator.  Wraps Local JuMP NLP Evaluators.
mutable struct OptiGraphNLPEvaluator <: MOI.AbstractNLPEvaluator
    graph::OptiGraph
    nlps::Union{Nothing,Vector{MOI.AbstractNLPEvaluator}} #nlp evaluators
    has_nlobj
    n#num variables
    m#num constraints
    p#num link constraints
    ninds#variable indices per node
    minds
    pinds
    nnzs_hess_inds
    nnzs_jac_inds
    nnzs_link_jac_inds


    # timers
    eval_objective_timer::Float64
    eval_constraint_timer::Float64
    eval_objective_gradient_timer::Float64
    eval_constraint_jacobian_timer::Float64
    eval_hessian_lagrangian_timer::Float64
    function OptiGraphNLPEvaluator(graph::OptiGraph)
        optinodes = all_nodes(graph)
        linkedges = all_edges(graph)

        K = length(optinodes)

        #num variables in optigraph
        ns= [num_variables(moi_optimizer(optinode)) for optinode in optinodes]
        n = sum(ns)
        ns_cumsum = cumsum(ns)

        #num constraints
        ms= [num_constraints(moi_optimizer(optinode)) for optinode in optinodes]
        m = sum(ms)
        ms_cumsum = cumsum(ms)

        #hessian nonzeros
        nnzs_hess = [get_nnz_hess(moi_optimizer(optinode)) for optinode in optinodes]
        nnzs_hess_cumsum = cumsum(nnzs_hess)
        nnz_hess = sum(nnzs_hess)

        #jacobian nonzeros
        nnzs_jac = [get_nnz_jac(moi_optimizer(optinode)) for optinode in optinodes]
        nnzs_jac_cumsum = cumsum(nnzs_jac)
        nnz_jac = sum(nnzs_jac)

        #link jacobian nonzeros
        nnzs_link_jac = [get_nnz_link_jac(linkedge) for linkedge in linkedges]
        nnzs_link_jac_cumsum = cumsum(nnzs_link_jac)
        nnz_link_jac = isempty(nnzs_link_jac) ? 0 : sum(nnzs_link_jac)

        #variable indices and constraint indices
        ninds = [(i==1 ? 0 : ns_cumsum[i-1])+1:ns_cumsum[i] for i=1:K]
        minds = [(i==1 ? 0 : ms_cumsum[i-1])+1:ms_cumsum[i] for i=1:K]

        #nonzero indices for hessian and jacobian
        nnzs_hess_inds = [(i==1 ? 0 : nnzs_hess_cumsum[i-1])+1:nnzs_hess_cumsum[i] for i=1:K]
        nnzs_jac_inds = [(i==1 ? 0 : nnzs_jac_cumsum[i-1])+1:nnzs_jac_cumsum[i] for i=1:K]

        #num linkedges
        Q = length(linkedges)
        ps= [num_linkconstraints(optiedge) for optiedge in linkedges]
        ps_cumsum =  cumsum(ps)
        p = sum(ps)
        pinds = [(i==1 ? m : m+ps_cumsum[i-1])+1:m+ps_cumsum[i] for i=1:Q]

        #link jacobian nonzero indices
        nnzs_link_jac_inds = [(i==1 ? nnz_jac : nnz_jac+nnzs_link_jac_cumsum[i-1])+1: nnz_jac + nnzs_link_jac_cumsum[i] for i=1:Q]

        d = new(graph)
        d.n = n
        d.m = m
        d.p = p
        d.ninds = ninds
        d.minds = minds
        d.pinds = pinds
        d.nnzs_hess_inds = nnzs_hess_inds
        d.nnzs_jac_inds = nnzs_jac_inds
        d.nnzs_link_jac_inds = d.nnzs_link_jac_inds

        #set_optimizer(getmodel(optinodes[k]),Optimizer)
        d.eval_objective_timer = 0
        d.eval_constraint_timer = 0
        d.eval_objective_gradient_timer = 0
        d.eval_constraint_jacobian_timer = 0
        d.eval_hessian_lagrangian_timer = 0
        return d
    end
end

function MOI.initialize(d::OptiGraphNLPEvaluator, requested_features::Vector{Symbol})
    #nldata::_NLPData = d.m.nlp_data
    graph = d.graph

    optinodes = all_nodes(graph)
    #linkedges = all_edges(graph)

    #Check for empty optinodes
    # for optinode in optinodes
    #     num_variables(optinode) == 0 && error("Detected optinode with 0 variables.  The Plasmo NLP interface does not yet support optinodes with zero variables.")
    # end

    #Initialize each optinode with the requested features
    #TODO: Each optinode needs to be initialized.
    #@blas_safe_threads for k=1:length(optinodes)
    for k = 1:length(optinodes)
        #Initialize each optinode evaluator
        d_node = JuMP.NLPEvaluator(optinodes[k].model)
        MOI.initialize(d_node,requested_features)
    end
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

function jacobian_structure(graph::OptiGraph,I,J,ninds,minds,pinds,
    nnzs_jac_inds,nnzs_link_jac_inds,
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

#@blas_safe_threads
const blas_num_threads = Ref{Int}()
function set_blas_num_threads(n::Integer;permanent::Bool=false)
    permanent && (blas_num_threads[]=n)
    BLAS.set_num_threads(n) # might be mkl64 or openblas64
    ccall((:mkl_set_dynamic, libmkl32),
          Cvoid,
          (Ptr{Int32},),
          Ref{Int32}(0))
    ccall((:mkl_set_num_threads, libmkl32),
          Cvoid,
          (Ptr{Int32},),
          Ref{Int32}(n))
    ccall((:openblas_set_num_threads, libopenblas32),
          Cvoid,
          (Ptr{Int32},),
          Ref{Int32}(n))
end
macro blas_safe_threads(args...)
    code = quote
        set_blas_num_threads(1)
        Threads.@threads($(args...))
        set_blas_num_threads(blas_num_threads[])
    end
    return esc(code)
end

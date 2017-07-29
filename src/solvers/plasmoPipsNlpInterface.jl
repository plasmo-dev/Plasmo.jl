# Plasmo Interface to Pips-NLP

module PlasmoPipsNlpInterface

importall MathProgBase.SolverInterface
import MPI
import JuMP
import Plasmo
include("PipsNlpSolver.jl")
using .PipsNlpSolver
export pipsnlp_solve

function convert_to_c_idx(indicies)
    for i in 1:length(indicies)
        indicies[i] = indicies[i] - 1
    end
end

type ModelData
    d    #NLP evaluator
    n::Int
    m::Int
    local_m::Int
    jacnnz::Int
    hessnnz::Int
    firstIeq::Vector{Int}           #row index of equality constraint in 1st stage
    firstJeq::Vector{Int}           #column index of equality constraint in 1st stage
    firstVeq::Vector{Float64}       #coefficient of variable in equality constraint in 1st stage
    secondIeq::Vector{Int}          #row index of equality constraint in 2nd stage
    secondJeq::Vector{Int}          #column index of equality constraint in 2nd stage
    secondVeq::Vector{Float64}
    firstIineq::Vector{Int}
    firstJineq::Vector{Int}
    firstVineq::Vector{Float64}
    secondIineq::Vector{Int}
    secondJineq::Vector{Int}
    secondVineq::Vector{Float64}
    num_eqconnect::Int
    num_ineqconnect::Int
    eqconnect_lb::Vector{Float64}
    eqconnect_ub::Vector{Float64}
    ineqconnect_lb::Vector{Float64}
    ineqconnect_ub::Vector{Float64}
    eq_idx::Vector{Int}
    ineq_idx::Vector{Int}
    firstJeqmat
    secondJeqmat
    firstJineqmat
    secondJineqmat
    linkIeq::Vector{Int}
    linkJeq::Vector{Int}
    linkVeq::Vector{Float64}
    linkIineq::Vector{Int}
    linkJineq::Vector{Int}
    linkVineq::Vector{Float64}
    x_sol::Vector{Float64}
    coreid::Int
    loaded::Bool
    local_unsym_hessnnz::Int
end
ModelData() = ModelData(nothing,0,0,0,0,0,Int[],Int[], Float64[], Int[], Int[], Float64[],Int[],Int[],Float64[], Int[], Int[], Float64[], 0, 0, Float64[],Float64[],Float64[],Float64[], Int[], Int[],nothing, nothing, nothing, nothing, Int[],Int[], Float64[], Int[], Int[], Float64[],Float64[], 0, false, 0)


#Helper function
function getData(m::JuMP.Model)
    if haskey(m.ext, :Data)
        return m.ext[:Data]
    else
        error("This functionality is only available to model with extension data")
    end
end

#also add a solve function that takes a master subgraph.  aggregate graphs into nodes(models) and pass to PIPS
# function ParPipsNlp_solve(graph::PlasmoGraph,master::PlasmoGraph,children::Vector{PlasmoGraph})
#     submodels = [getmodel(child) for child in children]
#     scen = length(children)
#     modelList = [getmodel(master); submodels]
# end

function pipsnlp_solve(graph::Plasmo.PlasmoGraph,master_node::Plasmo.NodeOrEdge,children_nodes::Vector{Plasmo.NodeOrEdge})
    #need to check that the structure makes sense

    submodels = [Plasmo.getmodel(child) for child in children_nodes]
    scen = length(children_nodes)

    master = Plasmo.getmodel(master_node)
    modelList = [master; submodels]

    #Add ModelData to each model
    for (idx,node) in enumerate(modelList)
        node.ext[:Data] = ModelData()
    end

    master_linear_lb = []
    master_linear_ub = []

    linkconstraints = Plasmo.getlinkconstraints(graph) #get all of the link constraints in the graph
    #get arrays of lower and upper bounds for each link constraint
    for con in linkconstraints
        push!(master_linear_lb,con.lb)
        push!(master_linear_ub,con.ub)
    end

    nlinkeq = 0
    nlinkineq = 0
    eqlink_lb = Float64[]
    eqlink_ub = Float64[]
    ineqlink_lb = Float64[]
    ineqlink_ub = Float64[]

    #go through the link constraints
    for c in 1:length(linkconstraints)
        coeffs = linkconstraints[c].terms.coeffs
        vars   = linkconstraints[c].terms.vars
        connect = false     #the constraint connects a single node to the master
        allconnect = false  #the constraint connects subproblems to eachother
        node = nothing

		for (it,ind) in enumerate(coeffs)              #for each coefficient in the constraint
            #if the constraint has a variable from a sub-node
            if (!connect) && (vars[it].m) != master    #if the variable isn't in the master model
                connect = true
                node = vars[it].m                      #the submodel
		    end
            #if the constraint actually involved multiple nodes
		    if connect && (vars[it].m != master) && (vars[it].m != node)
		       allconnect = true
		       break  #don't need to check every variable if this statement runs
		    end
	    end

    	if (connect) && (!allconnect)   #if there's a master child connection only
    	    local_data = getData(node)
    		if master_linear_lb[c] == master_linear_ub[c]  #if it's an equality constraint
                firstIeq = local_data.firstIeq
                firstJeq = local_data.firstJeq
                firstVeq = local_data.firstVeq
                secondIeq = local_data.secondIeq
                secondJeq = local_data.secondJeq
                secondVeq = local_data.secondVeq
                push!(local_data.eqconnect_lb, master_linear_lb[c])
                push!(local_data.eqconnect_ub, master_linear_ub[c])
                local_data.num_eqconnect += 1
                row = local_data.num_eqconnect
                for (it,ind) in enumerate(coeffs)
                    if (vars[it].m) == master
                           	  push!(firstIeq, row)
                          	  push!(firstJeq, vars[it].col)
                          	  push!(firstVeq, ind)
                    elseif (vars[it].m) == node
                           	  push!(secondIeq, row)
                          	  push!(secondJeq, vars[it].col)
                          	  push!(secondVeq, ind)
                    else
                      error("only supports connection between first stage variables and second stage variables from one specific scenario")
                    end
                end
    		else
                firstIineq = local_data.firstIineq
                firstJineq = local_data.firstJineq
                firstVineq = local_data.firstVineq
                secondIineq = local_data.secondIineq
                secondJineq = local_data.secondJineq
                secondVineq = local_data.secondVineq

                push!(local_data.ineqconnect_lb, master_linear_lb[c])
                push!(local_data.ineqconnect_ub, master_linear_ub[c])

                local_data.num_ineqconnect += 1
                row = local_data.num_ineqconnect
                for (it,ind) in enumerate(coeffs)
                    if (vars[it].m) == master
                        push!(firstIineq, row)
                        push!(firstJineq, vars[it].col)
                        push!(firstVineq, ind)
                    elseif (vars[it].m) == node
                        push!(secondIineq, row)
                        push!(secondJineq, vars[it].col)
                        push!(secondVineq, ind)
                    else
                        error("only supports connection between first stage variables and second stage variables from one specific scenario")
                    end
                end
	        end
	    end

	    if (allconnect)
            if master_linear_lb[c] == master_linear_ub[c]
                nlinkeq = nlinkeq + 1
                push!(eqlink_lb, master_linear_lb[c])
                push!(eqlink_ub, master_linear_ub[c])
                row = nlinkeq
                for (it,ind) in enumerate(coeffs)
                    node = vars[it].m
                    local_data = getData(node)
                    linkIeq = local_data.linkIeq
                    linkJeq = local_data.linkJeq
                    linkVeq = local_data.linkVeq
                    push!(linkIeq, row)
                    push!(linkJeq, vars[it].col)
                    push!(linkVeq, ind)
                end
            else
                nlinkineq = nlinkineq + 1
                push!(ineqlink_lb, master_linear_lb[c])
                push!(ineqlink_ub, master_linear_ub[c])
                row = nlinkineq
                for (it,ind) in enumerate(coeffs)
                    node = vars[it].m
                    local_data = getData(node)
                    linkIineq = local_data.linkIineq
                    linkJineq = local_data.linkJineq
                    linkVineq = local_data.linkVineq
                    push!(linkIineq, row)
                    push!(linkJineq, vars[it].col)
                    push!(linkVineq, ind)
                end
            end
        end
    end
    #removeConnection(master, connectid)  #removes the linear constraints from the master model.  I don't add these to the master anyways
    master_data = getData(master)  #this isn't used anywhere?

    if haskey(master.ext, :nlinkeq)
        nlinkeq =  master.ext[:nlinkeq]
    end
    if haskey(master.ext, :nlinkineq)
        nlinkineq =  master.ext[:nlinkineq]
    end
    if haskey(master.ext, :eqlink_lb)
        eqlink_lb = copy(master.ext[:eqlink_lb])
        eqlink_ub = copy(master.ext[:eqlink_lb])
    end
    if haskey(master.ext, :eqlink_ub)
        eqlink_lb = copy(master.ext[:eqlink_ub])
        eqlink_ub = copy(master.ext[:eqlink_ub])
    end
    if haskey(master.ext, :ineqlink_lb)
        ineqlink_lb = copy(master.ext[:ineqlink_lb])
    end
    if haskey(master.ext, :ineqlink_ub)
        ineqlink_ub = copy(master.ext[:ineqlink_ub])
    end
    for (idx,node) in enumerate(modelList)
        local_data = getData(node)
        if haskey(node.ext, :linkIineq)
            local_data.linkIineq =  copy(node.ext[:linkIineq])
            node.ext[:linkIineq] = nothing
        end
        if haskey(node.ext, :linkJineq)
            local_data.linkJineq =  copy(node.ext[:linkJineq])
            node.ext[:linkJineq] = nothing
        end
        if haskey(node.ext, :linkVineq)
            local_data.linkVineq =  copy(node.ext[:linkVineq])
            node.ext[:linkVineq] = nothing
        end
        if haskey(node.ext, :linkIeq)
            local_data.linkIeq =  copy(node.ext[:linkIeq])
            node.ext[:linkIeq] = nothing
        end
        if haskey(node.ext, :linkJeq)
            local_data.linkJeq =  copy(node.ext[:linkJeq])
            node.ext[:linkJeq] = nothing
        end
        if haskey(node.ext, :linkVeq)
            local_data.linkVeq =  copy(node.ext[:linkVeq])
            node.ext[:linkVeq] = nothing
        end
    end


    function str_init_x0(nodeid, x0)
        node = modelList[nodeid+1]
        local_initval = copy(node.colVal)
        if any(isnan,node.colVal)
            local_initval[isnan.(node.colVal)] = 0
            local_initval = min.(max.(node.colLower,local_initval),node.colUpper)
        end
        original_copy(local_initval,x0)
    end


    function str_prob_info(nodeid,flag, mode,col_lb,col_ub,row_lb,row_ub)
	 	#comm = MPI.COMM_WORLD
        if flag != 1
            node = modelList[nodeid+1]
            local_data = getData(node)
            if(!local_data.loaded)
                local_data.loaded = true
                if (nodeid > 0)
                    if haskey(node.ext, :warmStart)
    	                if node.ext[:warmStart] == true
              	      	   solve(node)
                   	   	end
                    end
            	end

    			nlp_lb, nlp_ub = JuMP.constraintbounds(node)
         		local_data.local_m  = length(nlp_lb)

    			newRowId = Array{Int}(local_data.local_m)
    			eqId = 1
    			ineqId = 1
                for c in 1:local_data.local_m
                    if nlp_lb[c] == nlp_ub[c]
                        push!(local_data.eq_idx, c)
                        newRowId[c] = eqId
                        eqId +=  1
                    else
        				push!(local_data.ineq_idx, c)
        				newRowId[c] = ineqId
        				ineqId += 1
                    end
         		end
                local_data.m  = local_data.local_m + local_data.num_eqconnect + local_data.num_ineqconnect
                local_data.n = node.numCols
                local_data.x_sol = zeros(Float64,local_data.n)
                local_data.firstJeqmat = sparse(local_data.firstIeq, local_data.firstJeq, local_data.firstVeq, local_data.num_eqconnect, master_data.n)
                local_data.secondJeqmat = sparse(local_data.secondIeq, local_data.secondJeq, local_data.secondVeq, local_data.num_eqconnect, local_data.n)
                local_data.firstJineqmat = sparse(local_data.firstIineq, local_data.firstJineq, local_data.firstVineq, local_data.num_ineqconnect, master_data.n)
                local_data.secondJineqmat = sparse(local_data.secondIineq, local_data.secondJineq, local_data.secondVineq, local_data.num_ineqconnect, local_data.n)

                local_data.d = JuMP.NLPEvaluator(node)
                initialize(local_data.d, [:Grad,:Jac, :Hess])
                Ijac, Jjac = jac_structure(local_data.d)
                Ijaceq = Int[]
                Jjaceq = Int[]
                Ijacineq = Int[]
                Jjacineq = Int[]
                jac_eq_index = Int[]
                jac_ineq_index = Int[]
                for i in 1:length(Ijac)
                    c = Ijac[i]
                    if nlp_lb[c] == nlp_ub[c]
                        modifiedrow = newRowId[c]
                        push!(Ijaceq, modifiedrow)
                        push!(Jjaceq, Jjac[i])
                        push!(jac_eq_index, i)
                    else
                        modifiedrow = newRowId[c]
                        push!(Ijacineq, modifiedrow)
                        push!(Jjacineq, Jjac[i])
                        push!(jac_ineq_index,i)
                    end
                end

        		node.ext[:Ijaceq] = Ijaceq
         		node.ext[:Jjaceq] = Jjaceq
                node.ext[:Ijacineq] = Ijacineq
         		node.ext[:Jjacineq] = Jjacineq
         		node.ext[:jac_eq_index] = jac_eq_index
         		node.ext[:jac_ineq_index] = jac_ineq_index
         		Ihess, Jhess = hesslag_structure(local_data.d)

         		Hmap = Bool[]
         		node_Hrows = Int[]
         		node_Hcols = Int[]
         		for i in 1:length(Ihess)
            	    if Jhess[i] <= Ihess[i]
               	        push!(node_Hrows, Ihess[i])
                   		push!(node_Hcols, Jhess[i])
                   		push!(Hmap, true)
            	    else
                        push!(Hmap, false)
                    end
                end
         		val = ones(Float64,length(node_Hrows))
         		mat = sparse(node_Hrows,node_Hcols,val, local_data.n, local_data.n)
         		node.ext[:Hrows] = node_Hrows
         		node.ext[:Hcols] = node_Hcols
         		node.ext[:Hmap] = Hmap
         		local_hessnnz = length(mat.rowval)
         		local_data.local_unsym_hessnnz = length(Ihess)
         		local_data.hessnnz = local_hessnnz
		    end

	 	    if(mode == :Values)
               	nlp_lb, nlp_ub = JuMP.constraintbounds(node)
    			eq_lb=Float64[]
    			eq_ub=Float64[]
    			ineq_lb=Float64[]
    			ineq_ub=Float64[]
    			for i in 1: length(nlp_lb)
    			    if nlp_lb[i] == nlp_ub[i]
    			       push!(eq_lb, nlp_lb[i])
    			       push!(eq_ub, nlp_ub[i])
    			    else
    			       push!(ineq_lb, nlp_lb[i])
    			       push!(ineq_ub, nlp_ub[i])
    			    end
    			end

    			if nodeid !=  0
    			   eq_lb = [eq_lb; local_data.eqconnect_lb]
    			   eq_ub = [eq_ub; local_data.eqconnect_ub]
    			   ineq_lb = [ineq_lb; local_data.ineqconnect_lb]
    			   ineq_ub = [ineq_ub; local_data.ineqconnect_ub]
    			end

    			original_copy([eq_lb;ineq_lb], row_lb)
    			original_copy([eq_ub;ineq_ub], row_ub)
    			original_copy(node.colLower, col_lb)
    			original_copy(node.colUpper, col_ub)
            end
		    return (local_data.n,local_data.m)
		else
		    if(mode == :Values)
                original_copy([eqlink_lb; ineqlink_lb], row_lb)
                original_copy([eqlink_ub; ineqlink_ub], row_ub)
            end
            return (0, nlinkeq + nlinkineq)
		end
    end

    function str_eval_f(nodeid,x0,x1)
    	node = modelList[nodeid+1]
        local_data = getData(node)
        local_d = getData(node).d
        if nodeid ==  0
            local_x = x0
        else
            local_x = x1
        end
        local_scl = (node.objSense == :Min) ? 1.0 : -1.0
        f = local_scl*eval_f(local_d,local_x)
        return f
    end

    function str_eval_g(nodeid,x0,x1,new_eq_g, new_inq_g)
        node = modelList[nodeid+1]
        local_data = getData(node)
        local_d = getData(node).d
        if nodeid ==  0
            local_x = x0
        else
            local_x = x1
        end
        local_g = Array{Float64}(local_data.local_m)
        eval_g(local_d, local_g, local_x)
        new_eq_g[1:end] = [local_g[local_data.eq_idx]; local_data.firstJeqmat*x0+local_data.secondJeqmat*x1]
        new_inq_g[1:end] = [local_g[local_data.ineq_idx]; local_data.firstJineqmat*x0+local_data.secondJineqmat*x1]
	    return Int32(1)
    end

    function str_write_solution(id::Integer, x::Vector{Float64}, y_eq::Vector{Float64}, y_ieq::Vector{Float64})
        node = modelList[id+1]
        local_data = getData(node)
        local_data.x_sol = copy(x)
        r = MPI.Comm_rank(comm)
        local_data.coreid = r
    end


    function str_eval_grad_f(rowid,colid,x0,x1,new_grad_f)
    node = modelList[rowid+1]
    if rowid == colid
        local_data = getData(node)
        local_d = getData(node).d
        if colid ==  0
            local_x = x0
        else
            local_x = x1
        end
        local_grad_f = Array{Float64}(local_data.n)
        eval_grad_f(local_d, local_grad_f, local_x)
        local_scl = (node.objSense == :Min) ? 1.0 : -1.0
        scale!(local_grad_f,local_scl)
        original_copy(local_grad_f, new_grad_f)
    elseif colid == 0
        new_grad_f[1:end] = 0
    else
        assert(false)
    end
    return Int32(1)
    end

    function array_copy(src,dest)
        assert(length(src)==length(dest))
        for i in 1:length(src)
            dest[i] = src[i]-1
        end
    end

    function original_copy(src,dest)
        assert(length(src)==length(dest))
        for i in 1:length(src)
            dest[i] = src[i]
        end
    end

    function str_eval_jac_g(rowid,colid,flag, x0,x1,mode,e_rowidx,e_colptr,e_values,i_rowidx,i_colptr,i_values)
        if flag != 1
            node = modelList[rowid+1]
            local_data = getData(node)
            local_m_eq = length(local_data.eq_idx)
            local_m_ineq = length(local_data.ineq_idx)
            if mode == :Structure
                if (rowid == colid)
                    Ieq=[node.ext[:Ijaceq];local_data.secondIeq + local_m_eq]
                    Jeq=[node.ext[:Jjaceq];local_data.secondJeq]
                    Veq= ones(Float64, length(Ieq))
                    Iineq=[node.ext[:Ijacineq];local_data.secondIineq + local_m_ineq]
                    Jineq=[node.ext[:Jjacineq];local_data.secondJineq]
                    Vineq=ones(Float64, length(Iineq))
                    eqmat = sparse(Ieq, Jeq, Veq, local_m_eq + local_data.num_eqconnect, local_data.n)
                    ineqmat = sparse(Iineq, Jineq, Vineq, local_m_ineq + local_data.num_ineqconnect, local_data.n)
                else
                    eqmat = sparse(local_m_eq + local_data.firstIeq, local_data.firstJeq, local_data.firstVeq, local_m_eq + local_data.num_eqconnect, master_data.n)
                    ineqmat = sparse(local_m_ineq + local_data.firstIineq, local_data.firstJineq, local_data.firstVineq, local_m_ineq + local_data.num_ineqconnect, master_data.n)
                end
                return(length(eqmat.rowval), length(ineqmat.rowval))
            else
                if rowid == colid
                    if colid ==  0
                        local_x = x0
                    else
                        local_x = x1
                    end
                    local_values = Array{Float64}(length(node.ext[:Ijaceq])+length(node.ext[:Ijacineq]))
                    eval_jac_g(local_data.d, local_values, local_x)
                    jac_eq_index = node.ext[:jac_eq_index]
                    jac_ineq_index = node.ext[:jac_ineq_index]
                    Ieq=[node.ext[:Ijaceq];local_data.secondIeq + local_m_eq]
                    Jeq=[node.ext[:Jjaceq];local_data.secondJeq]
                    Veq=[local_values[jac_eq_index];local_data.secondVeq]
                    Iineq=[node.ext[:Ijacineq];local_data.secondIineq + local_m_ineq]
                    Jineq=[node.ext[:Jjacineq];local_data.secondJineq]
                    Vineq=[local_values[jac_ineq_index];local_data.secondVineq]
                    eqmat = sparseKeepZero(Ieq, Jeq, Veq, local_m_eq + local_data.num_eqconnect, local_data.n)
                    ineqmat = sparseKeepZero(Iineq, Jineq, Vineq, local_m_ineq + local_data.num_ineqconnect, local_data.n)
                else
                    eqmat = sparseKeepZero(local_m_eq + local_data.firstIeq, local_data.firstJeq, local_data.firstVeq, local_m_eq + local_data.num_eqconnect, master_data.n)
                    ineqmat = sparseKeepZero(local_m_ineq + local_data.firstIineq, local_data.firstJineq, local_data.firstVineq, local_m_ineq + local_data.num_ineqconnect, master_data.n)
                end
                if length(eqmat.nzval) > 0
                    array_copy(eqmat.rowval,e_rowidx)
                    array_copy(eqmat.colptr,e_colptr)
                    original_copy(eqmat.nzval,e_values)
                end
                if length(ineqmat.nzval) > 0
                    array_copy(ineqmat.rowval,i_rowidx)
                    array_copy(ineqmat.colptr,i_colptr)
                    original_copy(ineqmat.nzval, i_values)
                end
            end
        else
            node = modelList[rowid+1]
            local_data = getData(node)
            linkIeq = local_data.linkIeq
            linkJeq = local_data.linkJeq
            linkVeq = local_data.linkVeq
            linkIineq = local_data.linkIineq
            linkJineq = local_data.linkJineq
            linkVineq = local_data.linkVineq

            if mode == :Structure
                return(length(linkVeq), length(linkVineq))
            else
                eqmat = sparse(linkIeq, linkJeq, linkVeq, nlinkeq, local_data.n)
                ineqmat = sparse(linkIineq, linkJineq, linkVineq, nlinkineq, local_data.n)
                if length(eqmat.nzval) > 0
                    array_copy(eqmat.rowval,e_rowidx)
                    array_copy(eqmat.colptr,e_colptr)
                    original_copy(eqmat.nzval,e_values)
                end
                if length(ineqmat.nzval) > 0
                    array_copy(ineqmat.rowval,i_rowidx)
                    array_copy(ineqmat.colptr,i_colptr)
                    original_copy(ineqmat.nzval, i_values)
                end
            end
        end
        return Int32(1)
    end

    function str_eval_h(rowid,colid,x0,x1,obj_factor,lambda,mode,rowidx,colptr,values)
        node = modelList[colid+1]
        local_data = getData(node)
        if mode == :Structure
            if rowid == colid
                node_Hrows  = node.ext[:Hrows]
                node_Hcols = node.ext[:Hcols]
                node_val = ones(Float64,length(node_Hrows))
                mat = sparseKeepZero(node_Hrows,node_Hcols,node_val, local_data.n, local_data.n)
                return length(mat.rowval)
            elseif colid == 0
                node_Hrows  = node.ext[:Hrows]
                node_Hcols = node.ext[:Hcols]
                node_Hrows,node_Hcols = exchange(node_Hrows,node_Hcols)
                node_val = ones(Float64,length(node_Hrows))
                mat = sparseKeepZero(node_Hrows,node_Hcols,node_val, local_data.n, local_data.n)
                return length(mat.rowval)
            else
                return 0
            end
        else
            if rowid==colid
                node_Hmap = node.ext[:Hmap]
                node_Hrows  = node.ext[:Hrows]
                node_Hcols = node.ext[:Hcols]
                if colid ==  0
                    local_x = x0
                else
                    local_x = x1
                end
                local_unsym_values = Array{Float64}(local_data.local_unsym_hessnnz)
                node_val = ones(Float64,length(node_Hrows))
                local_scl = (node.objSense == :Min) ? 1.0 : -1.0
                local_m_eq = length(local_data.eq_idx)
                local_m_ineq = length(local_data.ineq_idx)
                local_lambda = zeros(Float64, local_data.local_m)
                for i in 1:local_m_eq
                    local_lambda[local_data.eq_idx[i]] = lambda[i]
                end
                for i in 1:local_m_ineq
                    local_lambda[local_data.ineq_idx[i]] = lambda[i+local_m_eq]
                end

                eval_hesslag(local_data.d, local_unsym_values, local_x, obj_factor*local_scl, local_lambda)
                local_sym_index=1
                for i in 1:local_data.local_unsym_hessnnz
                    if node_Hmap[i]
                        node_val[local_sym_index] = local_unsym_values[i]
                        local_sym_index +=1
                    end
                end
                node_Hrows,node_Hcols = exchange(node_Hrows,node_Hcols)
                mat = sparseKeepZero(node_Hrows,node_Hcols,node_val, local_data.n, local_data.n)
                array_copy(mat.rowval,rowidx)
                array_copy(mat.colptr,colptr)
                original_copy(mat.nzval,values)
            elseif colid ==	0
                node_Hrows  = node.ext[:Hrows]
                node_Hcols = node.ext[:Hcols]
                node_val = zeros(Float64,length(node_Hrows))
                node_Hrows,node_Hcols = exchange(node_Hrows,node_Hcols)
                mat = sparseKeepZero(node_Hrows,node_Hcols,node_val, local_data.n, local_data.n)
                array_copy(mat.rowval,rowidx)
                array_copy(mat.colptr,colptr)
                original_copy(mat.nzval,values)
            else
            end
        end
        return Int32(1)
    end

    #MPI.Init()
    comm = MPI.COMM_WORLD
    if(MPI.Comm_rank(comm) == 0)
        tic()
    end
    #Create FakeModel (The PIPS interface model) and pass all the functions it requires
    model = FakeModel(:Min,0, scen,
    str_init_x0, str_prob_info, str_eval_f, str_eval_g, str_eval_grad_f, str_eval_jac_g, str_eval_h,str_write_solution)
    prob = createProblemStruct(comm, model, true)
    ret = solveProblemStruct(prob)
    root = 0
    r = MPI.Comm_rank(comm)

    if(MPI.Comm_rank(comm) == 0)
        println("init_x0  ",prob.t_jl_init_x0)
        println("str_init_x0  ", prob.t_jl_str_prob_info)
        println("eval_f  ", prob.t_jl_eval_f)
        println("eval_g0  ",prob.t_jl_eval_g)
        println("eval_grad_f  ", prob.t_jl_eval_grad_f)
        println("eval_jac  ", prob.t_jl_eval_jac_g)
        println("str_eval_jac  ", prob.t_jl_str_eval_jac_g)
        println("eval_h  ",  prob.t_jl_eval_h)
        println("str_eval_h ",  prob.t_jl_str_eval_h)
        println("eval_write_solution  ",  prob.t_jl_write_solution)
        println("Solution time:   ",  toq(), " (s)")
    end

    for (idx,node) in enumerate(modelList)  #set solution values for each model
        local_data = getData(node)
        if idx != 1
            coreid = zeros(Int, 1)
            sc = MPI.Reduce(local_data.coreid, MPI.SUM, root, comm)
            if r == root
                coreid[1] = sc
            end
            MPI.Bcast!(coreid, length(coreid), root, comm)
            n = zeros(Int, 1)
            n[1] = local_data.n
            MPI.Bcast!(n,      length(n),      coreid[1], comm)
            if r != coreid[1]
                local_data.n = n[1]
                local_data.x_sol = zeros(Float64,local_data.n)
            end
            MPI.Bcast!(local_data.x_sol, local_data.n, coreid[1], comm)
            node.colVal = local_data.x_sol
        else
            node.colVal = local_data.x_sol
        end
    end
    #MPI.Finalize()

    status = :Unknown
    if ret == 0
        status = :Solve_Succeeded
        Plasmo._setobjectivevalue(graph,prob.t_jl_eval_f)
    elseif ret == 1
        status = :Not_Finished
    elseif	ret == 2
        status = :Maximum_Iterations_Exceeded
    elseif	ret == 3
        stauts = :Infeasible_Problem_Detected
    elseif ret == 4
        status = :Restoration_needed
    else
    end

    return status
end  #end pips_nlp_solve


#############################################
# Helpers
#############################################
function exchange(a,b)
	 temp = a
         a=b
         b=temp
	 return (a,b)
end

function sparseKeepZero{Tv,Ti<:Integer}(I::AbstractVector{Ti},
    J::AbstractVector{Ti},
    V::AbstractVector{Tv},
    nrow::Integer, ncol::Integer)
    N = length(I)
    if N != length(J) || N != length(V)
        throw(ArgumentError("triplet I,J,V vectors must be the same length"))
    end
    if N == 0
        return spzeros(eltype(V), Ti, nrow, ncol)
    end

    # Work array
    Wj = Array{Ti}(max(nrow,ncol)+1)
    # Allocate sparse matrix data structure
    # Count entries in each row
    Rnz = zeros(Ti, nrow+1)
    Rnz[1] = 1
    nz = 0
    for k=1:N
        iind = I[k]
        iind > 0 || throw(ArgumentError("all I index values must be > 0"))
        iind <= nrow || throw(ArgumentError("all I index values must be ≤ the number of rows"))
        Rnz[iind+1] += 1
        nz += 1
    end
    Rp = cumsum(Rnz)
    Ri = Array{Ti}(nz)
    Rx = Array{Tv}(nz)

    # Construct row form
    # place triplet (i,j,x) in column i of R
    # Use work array for temporary row pointers
    @simd for i=1:nrow; @inbounds Wj[i] = Rp[i]; end
    @inbounds for k=1:N
        iind = I[k]
        jind = J[k]
        jind > 0 || throw(ArgumentError("all J index values must be > 0"))
        jind <= ncol || throw(ArgumentError("all J index values must be ≤ the number of columns"))
        p = Wj[iind]
        Vk = V[k]
        Wj[iind] += 1
        Rx[p] = Vk
        Ri[p] = jind
    end

    # Reset work array for use in counting duplicates
    @simd for j=1:ncol; @inbounds Wj[j] = 0; end

    # Sum up duplicates and squeeze
    anz = 0
    @inbounds for i=1:nrow
        p1 = Rp[i]
        p2 = Rp[i+1] - 1
        pdest = p1
        for p = p1:p2
            j = Ri[p]
            pj = Wj[j]
            if pj >= p1
                Rx[pj] = Rx[pj] + Rx[p]
            else
                Wj[j] = pdest
                if pdest != p
                    Ri[pdest] = j
                    Rx[pdest] = Rx[p]
                end
                pdest += one(Ti)
            end
        end
        Rnz[i] = pdest - p1
        anz += (pdest - p1)
    end

    # Transpose from row format to get the CSC format
    RiT = Array{Ti}(anz)
    RxT = Array{Tv}(anz)

    # Reset work array to build the final colptr
    Wj[1] = 1
    @simd for i=2:(ncol+1); @inbounds Wj[i] = 0; end
    @inbounds for j = 1:nrow
        p1 = Rp[j]
        p2 = p1 + Rnz[j] - 1
        for p = p1:p2
            Wj[Ri[p]+1] += 1
        end
    end
    RpT = cumsum(Wj[1:(ncol+1)])

    # Transpose
    @simd for i=1:length(RpT); @inbounds Wj[i] = RpT[i]; end
    @inbounds for j = 1:nrow
        p1 = Rp[j]
        p2 = p1 + Rnz[j] - 1
        for p = p1:p2
            ind = Ri[p]
            q = Wj[ind]
            Wj[ind] += 1
            RiT[q] = j
            RxT[q] = Rx[p]
        end
    end

    return SparseMatrixCSC(nrow, ncol, RpT, RiT, RxT)
end

end #end module
# function removeConnection(master::JuMP.Model, deleterow)
#     deleteat!(master.linconstr,deleterow)
# end

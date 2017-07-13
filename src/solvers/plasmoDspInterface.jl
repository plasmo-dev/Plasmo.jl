# Plasmo Interface to Dsp
module PlasmoDspInterface

include("DspCInterface.jl")
#using .DspCInterface
#import .DspCInterface:DspModel,@dspccall
import .DspCInterface:DspModel,@dsp_ccall
import Plasmo
import JuMP

export dsp_solve

#Build up Dsp Model using structure from Plasmo
# This function is hooked by JuMP (see block.jl)
function dsp_solve(graph::Plasmo.PlasmoGraph,master_node::Plasmo.NodeOrEdge,children_nodes::Vector{Plasmo.NodeOrEdge}; suppress_warnings = false, options...)
    master = getmodel(master_node)
    submodels = [getmodel(child) for child in children_nodes]
    linkconstraints = getlinkconstraints(graph) #get all of the link constraints in the graph
    #scen = length(children_nodes)

    # parse options
    for (optname, optval) in options
        if optname == :param
            DspCInterface.readParamFile(Dsp.model, optval)
        elseif optname == :solve_type
            if optval in [:Dual, :Benders, :Extensive]
                Dsp.model.solve_type = optval
            else
                warn("solve_type $optval is not available.")
            end
        else
            warn("Options $optname is not available.")
        end
    end

    # load the Plasmo models to Dsp
    loadProblem(Dsp.model,graph, master, submodels)

    # solve
    DspCInterface.solve(Dsp.model)

    # solution status
    statcode = DspCInterface.getSolutionStatus(Dsp.model)
    stat = parseStatusCode(statcode)

    # Extract solution from the solver
    Dsp.model.numRows = DspCInterface.getNumRows(Dsp.model, 0) + DspCInterface.getNumRows(Dsp.model, 1) * DspCInterface.getNumScenarios(Dsp.model)
    Dsp.model.numCols = DspCInterface.getTotalNumCols(Dsp.model)

    #this should be the graph objective and column values?
    #TODO
    master.objVal = NaN
    master.colVal = fill(NaN, Dsp.model.numCols)

    if stat != :Optimal
        suppress_warnings || warn("Not solved to optimality, status: $stat")
    end

    if !(stat == :Infeasible || stat == :Unbounded)
        getDspSolution(master,submodels)
    end

    # Return the solve status
    stat
end

function loadProblem(dsp::DspModel,graph::Plasmo.PlasmoGraph, master::JuMP.Model, subproblems::Vector{JuMP.Model}, dedicatedMaster::Bool)
    check_problem(dsp)

    #if haskey(model.ext, :DspBlocks) #if there are children models given.....
    if length(subproblems) > 0
        loadStochasticProblem(dsp, graph, master,subproblems, dedicatedMaster;probabilties = Dict(zip(1:length(subproblems),fill(1/length(subproblems),length(subproblems)))))
    else #Do I even need to support this?
        warn("No blocks were defined.")
        loadDeterministicProblem(dsp, master)
    end
end
loadProblem(dsp::DspModel,master::JuMP.Model, subproblems::Vector{JuMP.Model}) = loadProblem(dsp, master, subproblems, true);

#TODO
function loadStochasticProblem(dsp::DspModel, graph::Plasmo.PlasmoGraph, master::JuMP.Model, subproblems::Vector{JuMP.Model}, dedicatedMaster::Bool;probabilities)
    #model was a Dsp JuMP model
    # get DspBlocks
    #blocks = model.ext[:DspBlocks]    #this is a blockstructure with ids and weights
    blocks = subproblems #maybe this will work?

    nscen  = dsp.nblocks
    ncols1 = master.numCols
    nrows1 = length(master.linconstr)
    ncols2 = 0
    nrows2 = 0
    #for s in values(blocks.children)
    for s in subproblems
        ncols2 = s.numCols
        nrows2 = length(s.linconstr)
        break #this only runs the loop once?
    end

    # set scenario indices for each MPI processor
    if dsp.comm_size > 1
        ncols2 = MPI.allreduce([ncols2], MPI.MAX, dsp.comm)[1]
        nrows2 = MPI.allreduce([nrows2], MPI.MAX, dsp.comm)[1]
    end

    @dsp_ccall("setNumberOfScenarios", Void, (Ptr{Void}, Cint), dsp.p, convert(Cint, nscen))
    @dsp_ccall("setDimensions", Void,
        (Ptr{Void}, Cint, Cint, Cint, Cint),
        dsp.p, convert(Cint, ncols1), convert(Cint, nrows1), convert(Cint, ncols2), convert(Cint, nrows2))

    # get problem data
    # this is the master model
    start, index, value, clbd, cubd, ctype, obj, rlbd, rubd = getDataFormat(master)

    @dsp_ccall("loadFirstStage", Void,
        (Ptr{Void}, Ptr{Cint}, Ptr{Cint}, Ptr{Cdouble}, Ptr{Cdouble},
            Ptr{Cdouble}, Ptr{UInt8}, Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cdouble}),
            dsp.p, start, index, value, clbd, cubd, ctype, obj, rlbd, rubd)

    for id in dsp.block_ids
        # model and probability
        #blk = blocks.children[id] #the sub model
        blk = subproblems[id]
        #probability = blocks.weight[id] #probability of this scenario
        probability = probabilities[id]
        linkcons = Plasmo.getlinkconstraints(blk)[graph]
        # get model data
        start, index, value, clbd, cubd, ctype, obj, rlbd, rubd = getDataFormat(master,blk,linkcons)
        @dsp_ccall("loadSecondStage", Void,
            (Ptr{Void}, Cint, Cdouble, Ptr{Cint}, Ptr{Cint}, Ptr{Cdouble}, Ptr{Cdouble},
                Ptr{Cdouble}, Ptr{UInt8}, Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cdouble}),
            dsp.p, id-1, probability, start, index, value, clbd, cubd, ctype, obj, rlbd, rubd)
    end

end

#TODO
function loadDeterministicProblem(dsp::DspModel, model::JuMP.Model)
    ncols = convert(Cint, model.numCols)
    nrows = convert(Cint, length(model.linconstr))
    start, index, value, clbd, cubd, ctype, obj, rlbd, rubd = getDataFormat(model)
    numels = length(index)
    @dsp_ccall("loadDeterministic", Void,
        (Ptr{Void}, Ptr{Cint}, Ptr{Cint}, Ptr{Cdouble}, Cint, Cint, Cint,
            Ptr{Cdouble}, Ptr{Cdouble}, Ptr{UInt8}, Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cdouble}),
            dsp.p, start, index, value, numels, ncols, nrows, clbd, cubd, ctype, obj, rlbd, rubd)
end

#This is used in getDSPSolution
function getNumBlockCols(dsp::DspModel, blocks::Dict{Int,JuMP.Model})
    check_problem(dsp)
    #blocks = m.ext[:DspBlocks].children
    #Might need to be smarter about his
    #blocks = collect(zip(1:length(subproblems),subproblems))
    # get number of block columns
    numBlockCols = Dict{Int,Int}()  #{block:num_cols}
    if dsp.comm_size > 1
        num_proc_blocks = convert(Vector{Cint}, MPI.Allgather(length(blocks), dsp.comm))
        #@show num_proc_blocks
        #@show collect(keys(blocks))
        block_ids = MPI.Allgatherv(collect(keys(blocks)), num_proc_blocks, dsp.comm)
        #@show block_ids
        ncols_to_send = Int[blocks[i].numCols for i in keys(blocks)]
        #@show ncols_to_send
        ncols = MPI.Allgatherv(ncols_to_send, num_proc_blocks, dsp.comm)
        #@show ncols
        for i in 1:dsp.nblocks
            setindex!(numBlockCols, ncols[i], block_ids[i])
        end
    else
        for b in blocks
            setindex!(numBlockCols, b.second.numCols, b.first)
        end
    end
    return numBlockCols
end

#this is used for a master model
function getDataFormat(model::JuMP.Model)

    # Column wise sparse matrix
    mat = JuMP.prepConstrMatrix(model)
    # Tranpose; now I have row-wise sparse matrix
    mat = mat'

    # sparse description
    start = convert(Vector{Cint}, mat.colptr - 1) #column
    index = convert(Vector{Cint}, mat.rowval - 1) #row index
    value = mat.nzval

    # column type
    ctype = ""
    for i = 1:length(model.colCat)
        if model.colCat[i] == :Int
            ctype = ctype * "I";
        elseif model.colCat[i] == :Bin
            ctype = ctype * "B";
        else
            ctype = ctype * "C";
        end
    end
    ctype = convert(Vector{UInt8}, ctype)

    # objective coefficients
    obj = JuMP.prepAffObjective(model)
    rlbd, rubd = JuMP.prepConstrBounds(model)

    # set objective sense
    if model.objSense == :Max
        obj *= -1
    end

    return start, index, value, model.colLower, model.colUpper, ctype, obj, rlbd, rubd
end

#Get the data format for a child node.  We also need to pass the child's linkconstraints
function getDataFormat(master::JuMP.Model,child::JuMP.Model,linkcons::Vector{JuMP.AbstractConstraint})
    # Column wise sparse matrix
    mat = JuMP.prepChildConstrMatrix(master,child,linkcons)
    # Tranpose; now I have row-wise sparse matrix
    mat = mat'

    # sparse description
    start = convert(Vector{Cint}, mat.colptr - 1) #column
    index = convert(Vector{Cint}, mat.rowval - 1) #row index
    value = mat.nzval

    # column type
    ctype = ""
    for i = 1:length(model.colCat)
        if model.colCat[i] == :Int
            ctype = ctype * "I";
        elseif model.colCat[i] == :Bin
            ctype = ctype * "B";
        else
            ctype = ctype * "C";
        end
    end
    ctype = convert(Vector{UInt8}, ctype)

    # objective coefficients
    obj = JuMP.prepAffObjective(model)

    allconstr = [linconstr;linkconstraints]
    child_linear_lb = []
    child_linear_ub = []

    #rlbd, rubd = JuMP.prepConstrBounds(model)
    for con in allconstr
        push!(child_linear_lb,con.lb)
        push!(child_linear_ub,con.ub)
    end
    rlbd = child_linear_lb
    rubd = child_linear_ub

    # set objective sense
    if model.objSense == :Max
        obj *= -1
    end

    return start, index, value, model.colLower, model.colUpper, ctype, obj, rlbd, rubd
end

function prepChildConstrMatrix(master::JuMP.Model,child::JuMP.Model,linkconstraints::Vector{JuMP.AbstractConstraint})
    rind = Int[]
    cind = Int[]
    value = Float64[]
    linconstr = m.linconstr              #these should be local model constraints
    #linkconstr = getlinkconstraints(node)[graph]#the constraints that connect this model to the parent
    allconstr = [linconstr;linkconstraints]
    for (nrow,con) in enumerate(allconstr)
        aff = con.terms
        for (var,id) in zip(reverse(aff.vars), length(aff.vars):-1:1)
            push!(rind, nrow)  #each variable has a row index
            if allconstr[nrow].terms.vars[id].m == master   #if the variable belongs to the master, use the master column index
                push!(cind, var.col)
            elseif allconstr[nrow].terms.vars[id].m == child          #if it's a local variable to the subproblem
                push!(cind, blocks.parent.numCols + var.col)          #push the variable passed the master column
            end
            push!(value, aff.coeffs[id])
            # splice!(aff.vars, id)   #remove the variable and coefficient from aff
            # splice!(aff.coeffs, id)
        end
    end
    return sparse(rind, cind, value, length(allconstr), master.numCols + child.numCols)
end

function parseStatusCode(statcode::Integer)
    stat = :NotSolved
    if statcode == 3000
        stat = :Optimal
    elseif statcode == 3001
        stat = :Infeasible
    elseif statcode == 3002
        stat = :Unbounded
    elseif statcode in [3004,3007,3010]
        stat = :IterOrTimeLimit
    elseif statcode == 3005
        stat = :GapTolerance
    elseif statcode == 3006
        stat = :NodeLimit
    elseif statcode in [3008,3009,3014,3015,3016]
        stat = :UserLimit
    elseif statcode in [3011,3012,3013,3999]
        stat = :Error
    else
        stat = :Unknown
        warn("Unknown status: $statcode")
    end

    stat
end

function getDspSolution(master,subproblems)
    Dsp.model.primVal = DspCInterface.getPrimalBound(Dsp.model)
    Dsp.model.dualVal = DspCInterface.getDualBound(Dsp.model)
    if Dsp.model.solve_type == :Dual
        Dsp.model.rowVal = DspCInterface.getDualSolution(Dsp.model)
        #Need to get primal solution
    else
        Dsp.model.colVal = DspCInterface.getSolution(Dsp.model)
        if master != nothing
            # parse solution to each block
            #start with the master
            n_start = 1
            n_end = master.numCols
            master.colVal = Dsp.model.colVal[n_start:n_end]
            n_start += master.numCols
            #if haskey(m.ext, :DspBlocks) == true
            #blocks = m.ext[:DspBlocks].children
            blocks = collect(zip(1:length(subproblems),subproblems))
            numBlockCols = DspCInterface.getNumBlockCols(Dsp.model,blocks)
            for i in 1:Dsp.model.nblocks
                n_end += numBlockCols[i]
                if haskey(blocks, i)
                    # @show b
                    # @show n_start
                    # @show n_end
                    blocks[i].colVal = Dsp.model.colVal[n_start:n_end]
                end
                n_start += numBlockCols[i]
            end
        end
    end
    #set the graph objective
    if master != nothing
        master.objVal = Dsp.model.primVal
        # maximization?
        if m.objSense == :Max
            m.objVal *= -1
            Dsp.model.primVal *= -1
            Dsp.model.dualVal *= -1
        end
    end
end

end #end module

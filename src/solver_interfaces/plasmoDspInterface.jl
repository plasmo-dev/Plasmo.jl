# Plasmo Interface to Dsp
module PlasmoDspInterface

include("DspCInterface.jl")
Pkg.installed("MPI") == nothing || using MPI
#import .DspCInterface:DspModel,@dsp_ccall,check_problem
#using .DspCInterface
import .DspCInterface
import Plasmo
import JuMP

export dsp_solve

#Build up Dsp Model using structure from Plasmo
# This function is hooked by JuMP (see block.jl)
function dsp_solve(graph::Plasmo.PlasmoGraph,master_node::Plasmo.NodeOrEdge,children_nodes::Vector{Plasmo.NodeOrEdge};
                        probabilities = Dict(zip(1:length(children_nodes),fill(1/length(children_nodes),length(children_nodes)))),suppress_warnings = false, options...)
    master = Plasmo.getmodel(master_node)
    submodels = [Plasmo.getmodel(child) for child in children_nodes]
    linkconstraints = Plasmo.getlinkconstraints(graph) #get all of the link constraints in the graph

    dspmodel = DspCInterface.DspModel()
    DspCInterface.freeModel(dspmodel)
    # parse options
    for (optname, optval) in options
        if optname == :param
            DspCInterface.readParamFile(dspmodel, optval)
        elseif optname == :solve_type
            if optval in [:Dual, :Benders, :Extensive]
                dspmodel.solve_type = optval
            else
                warn("solve_type $optval is not available.")
            end
        else
            warn("Options $optname is not available.")
        end
    end

    nblocks = length(submodels)
    DspCInterface.setBlockIds(dspmodel, nblocks)
    #setBlockIds(dspmodel, nblocks)
    #println(dspmodel)
    # load the plasmo models to Dsp
    loadProblem(dspmodel,graph, master, submodels,probabilities)
    # println(DspCInterface.getTotalNumCols(dspmodel))
    # println(DspCInterface.getTotalNumRows(dspmodel))
    # println(DspCInterface.getNumCouplingRows(dspmodel))
    # solve
    DspCInterface.solve(dspmodel)

    # solution status
    statcode = DspCInterface.getSolutionStatus(dspmodel)
    stat = parseStatusCode(statcode)

    # Extract solution from the solver
    dspmodel.numRows = DspCInterface.getNumRows(dspmodel, 0) + DspCInterface.getNumRows(dspmodel, 1) * DspCInterface.getNumScenarios(dspmodel)
    dspmodel.numCols = DspCInterface.getTotalNumCols(dspmodel)

    #this should be the graph objective and column values?
    #TODO
    master.objVal = NaN
    master.colVal = fill(NaN, dspmodel.numCols)

    if stat != :Optimal
        suppress_warnings || warn("Not solved to optimality, status: $stat")
    end

    if !(stat == :Infeasible || stat == :Unbounded)
        getDspSolution(dspmodel,master,submodels)  #add solution data to master and children models
    end
    Plasmo._setobjectivevalue(graph,dspmodel.primVal)
    # Return the solve status
    return stat
    #return dspmodel
end

function loadProblem(dsp::DspCInterface.DspModel,graph::Plasmo.PlasmoGraph, master::JuMP.Model, subproblems::Vector{JuMP.Model}, dedicatedMaster::Bool,probabilities)
    DspCInterface.check_problem(dsp)

    #if haskey(model.ext, :DspBlocks) #if there are children models given.....
    if length(subproblems) > 0
        loadStochasticProblem(dsp, graph, master,subproblems, dedicatedMaster,probabilities)
        #loadStochasticProblem(dsp, graph, master,subproblems, dedicatedMaster,probabilities = Dict(zip(1:length(subproblems),fill(1.0,length(subproblems)))))

    else #Do I even need to support this?
        warn("No blocks were defined.")
        loadDeterministicProblem(dsp, master)
    end
end
loadProblem(dsp::DspCInterface.DspModel,graph::Plasmo.PlasmoGraph,master::JuMP.Model, subproblems::Vector{JuMP.Model},probabilites::Dict) = loadProblem(dsp,graph, master, subproblems, true,probabilites);

function loadStochasticProblem(dsp::DspCInterface.DspModel, graph::Plasmo.PlasmoGraph, master::JuMP.Model, subproblems::Vector{JuMP.Model}, dedicatedMaster::Bool, probabilities::Dict)
    # model was a Dsp JuMP model
    # get DspBlocks
    #blocks = model.ext[:DspBlocks]    #this is a blockstructure with ids and weights
    #blocks = subproblems #maybe this will work?

    nscen  = dsp.nblocks
    ncols1 = master.numCols
    nrows1 = length(master.linconstr)
    ncols2 = 0
    nrows2 = 0
    #for s in values(blocks.children)  #these are models
    #Do I need to figure out which variables are actually first stage?
    for s in subproblems
        node = Plasmo.getnode(s)
        link_cons = Plasmo.getlinkconstraints(node)[graph]  #link constraints specific to this subproblem
        ncols2 = s.numCols  #this is normally the number of second stage variables, but I'm lifting so....
        nrows2 = length(s.linconstr) + length(link_cons)
        break #this only runs the loop once?
    end

    # set scenario indices for each MPI processor
    if dsp.comm_size > 1
        ncols2 = MPI.allreduce([ncols2], MPI.MAX, dsp.comm)[1]
        nrows2 = MPI.allreduce([nrows2], MPI.MAX, dsp.comm)[1]
    end

    #Need to include linkconstraints on subproblems in dimensions
    # println()
    # @show nscen
    # @show ncols1
    # @show ncols2
    # @show nrows1
    # @show nrows2

    DspCInterface.@dsp_ccall("setNumberOfScenarios", Void, (Ptr{Void}, Cint), dsp.p, convert(Cint, nscen))
    DspCInterface.@dsp_ccall("setDimensions", Void,
        (Ptr{Void}, Cint, Cint, Cint, Cint),
        dsp.p, convert(Cint, ncols1), convert(Cint, nrows1), convert(Cint, ncols2), convert(Cint, nrows2))

    # get problem data
    # this is the master model
    start, index, value, clbd, cubd, ctype, obj, rlbd, rubd = getDataFormat(master)

    # println()
    # @show start
    # @show index
    # @show value
    # @show clbd
    # @show cubd
    # @show ctype
    # @show obj
    # @show rlbd
    # @show rubd


    DspCInterface.@dsp_ccall("loadFirstStage", Void,
        (Ptr{Void}, Ptr{Cint}, Ptr{Cint}, Ptr{Cdouble}, Ptr{Cdouble},
            Ptr{Cdouble}, Ptr{UInt8}, Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cdouble}),
            dsp.p, start, index, value, clbd, cubd, ctype, obj, rlbd, rubd)

    for id in dsp.block_ids
        # model and probability
        #blk = blocks.children[id] #the sub model
        blk = subproblems[id]  #need to be careful with block ids here
        node = Plasmo.getnode(blk)
        #probability = blocks.weight[id] #probability of this scenario
        probability = probabilities[id]
        linkcons = Plasmo.getlinkconstraints(node)[graph]
        # get model data
        start, index, value, clbd, cubd, ctype, obj, rlbd, rubd = getDataFormat(master,blk,linkcons)


        # println()
        # @show start
        # @show index
        # @show value
        # @show clbd
        # @show cubd
        # @show ctype
        # @show obj
        # @show typeof(obj)
        # @show rlbd
        # @show rubd
        # @show typeof(rlbd)

        #@show probability

        DspCInterface.@dsp_ccall("loadSecondStage", Void,
            (Ptr{Void}, Cint, Cdouble, Ptr{Cint}, Ptr{Cint}, Ptr{Cdouble}, Ptr{Cdouble},
                Ptr{Cdouble}, Ptr{UInt8}, Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cdouble}),
            dsp.p, id-1, probability, start, index, value, clbd, cubd, ctype, obj, rlbd, rubd)
    end
    #println(dsp)
end

#TODO
function loadDeterministicProblem(dsp::DspCInterface.DspModel, model::JuMP.Model)
    ncols = convert(Cint, model.numCols)
    nrows = convert(Cint, length(model.linconstr))
    start, index, value, clbd, cubd, ctype, obj, rlbd, rubd = getDataFormat(model)
    numels = length(index)
    DspCInterface.@dsp_ccall("loadDeterministic", Void,
        (Ptr{Void}, Ptr{Cint}, Ptr{Cint}, Ptr{Cdouble}, Cint, Cint, Cint,
            Ptr{Cdouble}, Ptr{Cdouble}, Ptr{UInt8}, Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cdouble}),
            dsp.p, start, index, value, numels, ncols, nrows, clbd, cubd, ctype, obj, rlbd, rubd)
end

#This is used in getDSPSolution
function getNumBlockCols(dsp::DspCInterface.DspModel, blocks::Dict{Int,JuMP.Model})
    DspCInterface.check_problem(dsp)
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
function getDataFormat(master::JuMP.Model,child::JuMP.Model,linkcons::Vector{Union{JuMP.AbstractConstraint, JuMP.ConstraintRef}})
    # Column wise sparse matrix
    mat = prepChildConstrMatrix(master,child,linkcons)
    # Tranpose; now I have row-wise sparse matrix
    mat = mat'

    # sparse description
    start = convert(Vector{Cint}, mat.colptr - 1) #column
    index = convert(Vector{Cint}, mat.rowval - 1) #row index
    value = mat.nzval

    # column type
    ctype = ""
    for i = 1:length(child.colCat)
        if child.colCat[i] == :Int
            ctype = ctype * "I";
        elseif child.colCat[i] == :Bin
            ctype = ctype * "B";
        else
            ctype = ctype * "C";
        end
    end
    ctype = convert(Vector{UInt8}, ctype)

    # objective coefficients
    obj = JuMP.prepAffObjective(child)

    linconstr = child.linconstr
    allconstr = [linconstr;linkcons]

    child_linear_lb = Array{Float64}(0)
    child_linear_ub = Array{Float64}(0)

    #rlbd, rubd = JuMP.prepConstrBounds(model)
    for con in allconstr
        push!(child_linear_lb,con.lb)
        push!(child_linear_ub,con.ub)
    end
    rlbd = child_linear_lb
    rubd = child_linear_ub

    # set objective sense
    if child.objSense == :Max
        obj *= -1
    end

    return start, index, value, child.colLower, child.colUpper, ctype, obj, rlbd, rubd
end

function prepChildConstrMatrix(master::JuMP.Model,child::JuMP.Model,linkconstraints::Vector{Union{JuMP.AbstractConstraint, JuMP.ConstraintRef}})
    rind = Int[]
    cind = Int[]
    value = Float64[]
    linconstr = child.linconstr              #these should be local model constraints
    #linkconstr = getlinkconstraints(node)[graph]#the constraints that connect this model to the parent
    allconstr = [linconstr;linkconstraints]
    for (nrow,con) in enumerate(allconstr)
        aff = con.terms
        for (var,id) in zip(reverse(aff.vars), length(aff.vars):-1:1)
            push!(rind, nrow)  #each variable has a row index
            if allconstr[nrow].terms.vars[id].m == master   #if the variable belongs to the master, use the master column index
                push!(cind, var.col)
            elseif allconstr[nrow].terms.vars[id].m == child          #if it's a local variable to the subproblem
                push!(cind, master.numCols + var.col)          #push the variable passed the master column
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

function getDspSolution(dspmodel,master,subproblems)
    dspmodel.primVal = DspCInterface.getPrimalBound(dspmodel)
    dspmodel.dualVal = DspCInterface.getDualBound(dspmodel)
    #println(dspmodel.primVal)
    if dspmodel.solve_type == :Dual
        dspmodel.rowVal = DspCInterface.getDualSolution(dspmodel)
        #Need to get primal solution
    else
        dspmodel.colVal = DspCInterface.getSolution(dspmodel)
    #    println(dspmodel.colVal)
        if master != nothing
            # parse solution to each block
            #start with the master
            n_start = 1
            n_end = master.numCols
            master.colVal = dspmodel.colVal[n_start:n_end]
            n_start += master.numCols
            #if haskey(m.ext, :DspBlocks) == true
            #blocks = m.ext[:DspBlocks].children
            blocks = Dict(zip(1:length(subproblems),subproblems))
            numBlockCols = getNumBlockCols(dspmodel,blocks)
            for i in 1:dspmodel.nblocks
                n_end += numBlockCols[i]
                if haskey(blocks, i)
                    # @show b
                    # @show n_start
                    # @show n_end
                    blocks[i].colVal = dspmodel.colVal[n_start:n_end]
                end
                n_start += numBlockCols[i]
            end
        end
    end
    #set the graph objective
    if master != nothing
        master.objVal = dspmodel.primVal
        # maximization?
        if master.objSense == :Max
            master.objVal *= -1
            dspmodel.primVal *= -1
            dspmodel.dualVal *= -1
        end
    end
end

end #end module

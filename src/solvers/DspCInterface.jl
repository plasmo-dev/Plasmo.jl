# Julia Interface to DSP
# Original interface by: Kibaek Kim; Argonne National Laboratory, 2016
module DspCInterface

#import ..Dsp
import Compat: String, unsafe_wrap
#import JuMP

Pkg.installed("MPI") == nothing || using MPI

#export DspModel, @dsp_ccall,freeDSP,

###############################################################################
# Help functions
###############################################################################
macro dsp_ccall(func, args...)
    @static if is_unix()
        return esc(quote
            ccall(($func, "libDsp"), $(args...))
        end)
    end
    @static if is_windows()
        return esc(quote
            ccall(($func, "libDsp"), stdcall, $(args...))
        end)
    end
end

type DspModel
    p::Ptr{Void}

    # Number of blocks
    nblocks::Int

    # solve_type should be one of these:
    # :Dual
    # :Benders
    # :Extensive
    solve_type

    numRows::Int
    numCols::Int
    primVal
    dualVal
    colVal::Vector{Float64}
    rowVal::Vector{Float64}

    # MPI settings
    comm
    comm_size::Int
    comm_rank::Int

    # Array of block ids:
    # The size of array is not necessarily same as nblocks,
    # as block ids may be distributed to multiple processors.
    block_ids::Vector{Integer}

    function DspModel()
        # assign Dsp pointer
        p = @dsp_ccall("createEnv", Ptr{Void}, ())
        # initialize variables
        nblocks = 0
        solve_type = :Dual
        numRows = 0
        numCols = 0
        primVal = NaN
        dualVal = NaN
        colVal = Vector{Float64}()
        rowVal = Vector{Float64}()
        comm = nothing
        comm_size = 1
        comm_rank = 0
        block_ids = Vector{Integer}()
        # create DspModel
        dsp = new(p, nblocks, solve_type, numRows, numCols, primVal, dualVal, colVal, rowVal, comm, comm_size, comm_rank, block_ids)
        # with finalizer
        finalizer(dsp, freeDSP)
        # return DspModel
        return dsp
    end
end

function freeDSP(dsp::DspModel)
    if dsp.p == C_NULL
        return
    else
        @dsp_ccall("freeEnv", Void, (Ptr{Void},), dsp.p)
        dsp.p = C_NULL
    end
    dsp.nblocks = 0
    dsp.solve_type = nothing
    dsp.numRows = 0
    dsp.numCols = 0
    dsp.primVal = NaN
    dsp.dualVal = NaN
    dsp.colVal = Vector{Float64}()
    dsp.rowVal = Vector{Float64}()
    return
end

function freeModel(dsp::DspModel)
    check_problem(dsp)
    @dsp_ccall("freeModel", Void, (Ptr{Void},), dsp.p)
    dsp.nblocks = 0
    dsp.numRows = 0
    dsp.numCols = 0
    dsp.primVal = NaN
    dsp.dualVal = NaN
    dsp.colVal = Vector{Float64}()
    dsp.rowVal = Vector{Float64}()
end

function check_problem(dsp::DspModel)
    if dsp.p == C_NULL
        error("Invalid DspModel")
    end
end

function readParamFile(dsp::DspModel, param_file::AbstractString)
    check_problem(dsp)
    @dsp_ccall("readParamFile", Void, (Ptr{Void}, Ptr{UInt8}), dsp.p, param_file);
end

###############################################################################
# Block IDs
###############################################################################
function setBlockIds(dsp::DspModel, nblocks::Integer)
    check_problem(dsp)
    # set number of blocks
    dsp.nblocks = nblocks
    # set MPI settings
    if isdefined(:MPI) && MPI.Initialized()
        dsp.comm = MPI.COMM_WORLD
        dsp.comm_size = MPI.Comm_size(dsp.comm)
        dsp.comm_rank = MPI.Comm_rank(dsp.comm)
    end
    #@show dsp.nblocks
    #@show dsp.comm
    #@show dsp.comm_size
    #@show dsp.comm_rank
    # get block ids with MPI settings
    dsp.block_ids = getBlockIds(dsp)
    #@show dsp.block_ids
    # send the block ids to Dsp
    @dsp_ccall("setIntPtrParam", Void, (Ptr{Void}, Ptr{UInt8}, Cint, Ptr{Cint}),
        dsp.p, "ARR_PROC_IDX", convert(Cint, length(dsp.block_ids)), convert(Vector{Cint}, dsp.block_ids - 1))
end

function getBlockIds(dsp::DspModel)
    check_problem(dsp)
    # processor info
    mysize = dsp.comm_size
    myrank = dsp.comm_rank
    # empty block ids
    proc_idx_set = Int[]
    # DSP is further parallelized with mysize > dsp.nblocks.
    modrank = myrank % dsp.nblocks
    # If we have more than one processor,
    # do not assign a sub-block to the master.
    if mysize > 1
        if myrank == 0
            return proc_idx_set
        end
        # exclude master
        mysize -= 1;
        modrank = (myrank-1) % dsp.nblocks
    end
    # assign sub-blocks in round-robin fashion
    for s = modrank:mysize:(dsp.nblocks-1)
        push!(proc_idx_set, s+1)
    end
    # return assigned block ids
    return proc_idx_set
end


###############################################################################
# Load problems
###############################################################################

function readSmps(dsp::DspModel, filename::AbstractString)
    # Check pointer to TssModel
    check_problem(dsp)
    # read smps files
    @dsp_ccall("readSmps", Void, (Ptr{Void}, Ptr{UInt8}), dsp.p, convert(Vector{UInt8}, filename))
    # set block Ids
    setBlockIds(dsp, getNumScenarios(dsp))
end



#################################################################################################

for func in [:freeSolver,
             :solveDe,
             :solveBd,
             :solveDd]
    strfunc = string(func)
    @eval begin
        function $func(dsp::DspModel)
            return @dsp_ccall($strfunc, Void, (Ptr{Void},), dsp.p)
        end
    end
end

for func in [:solveBdMpi, :solveDdMpi]
    strfunc = string(func)
    @eval begin
        function $func(dsp::DspModel, comm)
            return @dsp_ccall($strfunc, Void, (Ptr{Void}, MPI.CComm), dsp.p, convert(MPI.CComm, comm))
        end
    end
end

#Solve a DSP model
function solve(dsp::DspModel)
    check_problem(dsp)
    if dsp.comm_size == 1
        if dsp.solve_type == :Dual
            solveDd(dsp);
        elseif dsp.solve_type == :Benders
            solveBd(dsp);
        elseif dsp.solve_type == :Extensive
            solveDe(dsp);
        end
    elseif dsp.comm_size > 1
        if dsp.solve_type == :Dual
            solveDdMpi(dsp, dsp.comm);
        elseif dsp.solve_type == :Benders
            solveBdMpi(dsp, dsp.comm);
        elseif dsp.solve_type == :Extensive
            solveDe(dsp);
        end
    end
end


###############################################################################
# Get functions
###############################################################################
for (func,rtn) in [(:getNumScenarios, Cint),
                   (:getTotalNumCols, Cint),
                   (:getTotalNumRows, Cint),
                   (:getStatus, Cint),
                   (:getNumIterations, Cint),
                   (:getNumNodes, Cint),
                   (:getWallTime, Cdouble),
                   (:getPrimalBound, Cdouble),
                   (:getDualBound, Cdouble),
                   (:getNumCouplingRows, Cint)]
    strfunc = string(func)
    @eval begin
        function $func(dsp::DspModel)
            check_problem(dsp)
            return @dsp_ccall($strfunc, $rtn, (Ptr{Void},), dsp.p)
        end
    end
end
getSolutionStatus(dsp::DspModel) = getStatus(dsp)
function getNumRows(dsp::DspModel, num::Integer)
    @dsp_ccall("getNumRows", Cint, (Ptr{Void}, Cint), dsp.p, num)
end
function getNumCols(dsp::DspModel, num::Integer)
    @dsp_ccall("getNumCols", Cint, (Ptr{Void}, Cint), dsp.p, num)
end

function getObjCoef(dsp::DspModel)
    check_problem(dsp)
    num = getTotalNumCols()
    obj = Array(Cdouble, num)
    @dsp_ccall("getObjCoef", Void, (Ptr{Void}, Ptr{Cdouble}), dsp.p, obj)
    return obj
end

function getSolution(dsp::DspModel, num::Integer)
    sol = Array(Cdouble, num)
    @dsp_ccall("getPrimalSolution", Void, (Ptr{Void}, Cint, Ptr{Cdouble}), dsp.p, num, sol)
    return sol
end
getSolution(dsp::DspModel) = getSolution(dsp, getTotalNumCols(dsp))

function getDualSolution(dsp::DspModel, num::Integer)
    sol = Array(Cdouble, num)
    @dsp_ccall("getDualSolution", Void, (Ptr{Void}, Cint, Ptr{Cdouble}), dsp.p, num, sol)
    return sol
end
getDualSolution(dsp::DspModel) = getDualSolution(dsp, getNumCouplingRows(dsp))

###############################################################################
# Set functions
###############################################################################
function setSolverType(dsp::DspModel, solver)
    check_problem(dsp)
    solver_types = [:DualDecomp, :Benders, :ExtensiveForm]
    if solver in solver_types
        dsp.solver = solver
    else
        warn("Solver type $solver is invalid.")
    end
end

end # end of module

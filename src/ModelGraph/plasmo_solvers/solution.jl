mutable struct Solution
    problemname
    method::Symbol
    solvetime
    objval::Float64
    bestbound::Float64
    gap::Float64
    numiterations::Int64
    termination
    # Iteration Data
    iterval::Array{Float64,1}
    iterbound::Array{Float64,1}
    itertime::Array{Float64,1} # in seconds
    clocktime::Array{Float64,1}
    # Lagrange
    α
    step
end

function Solution(;method=:none)
    return Solution("",method,0,NaN,NaN,NaN,0,"Not Executed",Float64[],Float64[],Float64[],Float64[],Float64[],Float64[])
end

function saveiteration(s::Solution,tstamp::Float64,arr::Array{Float64,1},n=1)
    push!(s.iterval,arr[1])
    push!(s.iterbound,arr[2])
    push!(s.itertime,arr[3])
    push!(s.clocktime,arr[4])
    if length(arr) == 6 && s.method  == :dual_decomposition
        push!(s.α,arr[5])
        push!(s.step,arr[6])
    end
    if n == 1
        s.bestbound = maximum(s.iterbound)
        s.objval = minimum(s.iterval)
    else
        s.bestbound = minimum(s.iterbound)
        s.objval = maximum(s.iterval)
    end
    s.numiterations += 1
    s.gap = abs(s.objval - s.bestbound)/s.objval
    s.solvetime = tstamp
end

function Base.show(io::IO,s::Solution)
    println("-----------------")
    println(" SOLUTION SUMMARY")
    println("-----------------")
    println("Method: $(s.method)")
    println("Objective Value : $(s.objval)")
    println("Best Bound : $(s.bestbound)")
    println("Gap : $(round(s.gap*100,digits = 2)) %")
    println("Iterations : $(s.numiterations)")
    println("Solution Time : $(round(s.solvetime,digits = 2)) s")
    println("Termination : $(s.termination)")
end

function printiterationsummary(s::Solution; singleline=false)
    if singleline
        print("$(s.numiterations)  ")
        print("| $(round(s.iterval[end],digits = 4)) \t")
        print("$(round(s.iterbound[end],digits = 4)) \t")
        print("| $(round(s.objval,digits = 4)) \t")
        print("$(round(s.bestbound,digits = 4)) \t")
        print("| $(round(s.gap*100,digits = 2)) %\t")
        print("| $(round(s.clocktime[end],digits = 2)) s\n")
    else
        println("-----------------")
        println(" Iteration $(s.numiterations)")
        println("-----------------")
        println("Iteration Value : $(s.iterval[end])")
        println("Iteration Bound : $(s.iterbound[end])")
        println("Objective Value : $(s.objval)")
        println("Best Bound : $(s.bestbound)")
        println("Gap : $(round(s.gap*100,digits = 2)) %")
        println("Iteration Time : $(round(s.itertime[end],digits = 2)) s")
        println("Elapsed Time : $(round(s.clocktime[end],digits = 2)) s")
    end
end

function iterationheader()
    print("    |    Iteration\t")
    print("|     Best Bounds\t|\n")
    print("It  ")
    print("| Value \t")
    print("Bound \t")
    print("| Value \t")
    print("Bound \t")
    print("| Gap\t")
    print("| Time\n")
end

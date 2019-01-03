abstract type CutData end

struct BendersCutData <: CutData
  θk
  λk
  xk
end

struct LLIntegerCutData <: CutData
  θlb
  yk
end

struct IntegerCutData <: CutData
  yk
end

(==)(cd1::BendersCutData,cd2::BendersCutData) = (cd1.θk == cd2.θk) && (cd1.λk == cd2.λk) && (cd1.xk == cd2.xk)
(==)(cd1::LLIntegerCutData,cd2::LLIntegerCutData) = (cd1.θlb == cd2.θlb) &&  (cd1.yk == cd2.yk)
(==)(cd1::IntegerCutData,cd2::IntegerCutData) = (cd1.yk == cd2.yk)

"""
    bendersolve

    Solve a ModelTree object using nested benders decomposition.
"""
function bendersolve(tree::ModelTree; max_iterations::Int64=10, cuts::Array{Symbol,1}=[:LP], ϵ=1e-5,UBupdatefrequency=1,timelimit=3600,verbose=false,lp_solver = ClpSolver(),node_solver = ClpSolver())
    starttime = time()
    s = Solution(method=:benders)
    updatebound = true

    verbose && info("Preparing graph")
    bdprepare(tree,lp_solver,node_solver)
    n = getattribute(tree, :normalized)

    verbose && info("Solve relaxation and set LB")
    mf = getattribute(tree, :mflat)
    solve(mf,relaxation=true)
    LB = getobjectivevalue(getattribute(tree, :mflat))
    UB = Inf

    # Set bound to root node
    #rootnode = getattribute(graph, :roots)[1]
    rootnode = getroot(tree)
    rootmodel = getmodel(rootnode)
    @constraint(rootmodel, rootmodel.obj.aff >= LB)

    # Begin iterations
    for i in 1:max_iterations

        itertime = @elapsed begin

            updatebound = ((i-1) % UBupdatefrequency) == 0
            LB,UB = forwardstep(tree, cuts, updatebound)
            tstamp = time() - starttime

        end
        #itertime = toc()

        if n == 1
          saveiteration(s,tstamp,[UB,LB,itertime,tstamp],n)
        else
          saveiteration(s,tstamp,[n*LB,n*UB,itertime,tstamp],n)
        end
        printiterationsummary(s,singleline=false)

        if abs(UB-LB) < ϵ
          s.termination = "Optimal"
          return s
        end

        # Check time limit
        if tstamp > timelimit
          s.termination = "Time Limit"
          return s
        end

        if getattribute(tree, :stalled)
          s.termination = "Stalled"
          return s
        end
    end

    s.termination = "Max Iterations"
    return s
end

function forwardstep(tree::ModelTree, cuts::Array{Symbol,1}, updatebound::Bool)
  #levels = getattribute(tree, :levels)
  levels = tree.levels
  numlevels = length(levels)
  for level in 1:numlevels
    nodeslevel = levels[level]
    for node in nodeslevel
      solveprimalnode(node,tree,cuts,updatebound)
    end
  end
  LB = getattribute(tree, :LB)
  if updatebound
    iterUB = sum(getattribute(node, :preobjval) for node in getnodes(tree))
    setattribute(tree, :iterUB, iterUB)
    UB = min(getattribute(tree, :UB),iterUB)
    setattribute(tree, :UB, UB)
  else
    UB = getattribute(tree, :UB)
  end
  return LB,UB
end

function solveprimalnode(node::ModelNode, tree::ModelTree, cuts::Array{Symbol,1}, updatebound::Bool)
  # 1. Add cuts
  generatecuts(node,tree)
  # 2. Take x
  takex(node)
  # 3. solve
  if :LP in cuts
    solvelprelaxation(node)
  end
  if updatebound
    solvenodemodel(node,tree)
  end
  # 4. put x
  putx(node,tree)
  # 5. put cuts and nodebound
  putcutdata(node,tree,cuts)
end

function solvelprelaxation(node::ModelNode)
  model = getmodel(node)
  status = solve(model, relaxation = true)

  @assert status == :Optimal

  dualconstraints = getattribute(node, :linkconstraints)

  λnode = getdual(dualconstraints)
  nodebound = getobjectivevalue(model)

  setattribute(node, :bound, nodebound)
  setattribute(node, :λ, λnode)

  return status
end

function solvenodemodel(node::ModelNode,tree::ModelTree)
  model = getmodel(node)
  solve(model)
  if in_degree(tree,node) == 0 # Root node
    setattribute(tree, :LB, getobjectivevalue(model))
  end
  setattribute(node, :preobjval, JuMP.getvalue(model.ext[:preobj]))
end

function takex(node::ModelNode)
  xinvals = getattribute(node, :xin)
  xinvars = getattribute(node, :xinvars)
  if length(xinvals) > 0
    fix.(xinvars,xinvals)
  end
end

function putx(node::ModelNode,tree::ModelTree)
  childvars = getattribute(node,:childvars)
  children = out_neighbors(tree,node)
  length(children) == 0 && return true

  for child in children
    xnode = getvalue(childvars[getindex(tree,child)])
    setattribute(child,:xin, xnode)
  end
end

function putcutdata(node::ModelNode,tree::ModelTree,cuts::Array{Symbol,1})
  parents = in_neighbors(tree,node)
  length(parents) == 0 && return true
  parent = parents[1]    # Assume only one parent
  parentcuts = getattribute(parent, :cutdata)
  θk = getattribute(node,:bound)
  λk = getattribute(node,:λ)
  xk = getattribute(node,:xin)
  nodeindex = getindex(tree,node)
  if :LP in cuts || :Root in cuts
    bcd = BendersCutData(θk, λk, xk)
    push!(parentcuts[nodeindex],bcd)
  end
  if :LLinteger in cuts
    llintcd = LLIntegerCutData(θlb,xk)
    push!(parentcuts[nodeindex],llintcd)
  end
  if :Integer in cuts
    intcd = IntegerCutData(xk)
    push!(parentcuts[nodeindex],intcd)
  end
end

function generatecuts(node::ModelNode,tree::ModelTree)
    children = out_neighbors(tree,node)
    length(children) == 0 && return true

    cutdataarray = getattribute(node,:cutdata)
    previouscuts = getattribute(node,:prevcuts)
    thisitercuts = Dict()
    samecuts = Dict()
    for child in children
        childindex = getindex(tree,child)
        thisitercuts[childindex] = CutData[]
        samecuts[childindex] = Bool[]

        while length(cutdataarray[childindex]) > 0
            cutdata = pop!(cutdataarray[childindex])
            samecut = in(cutdata,previouscuts[childindex])
            push!(samecuts[childindex],samecut)
            samecut && continue
            if typeof(cutdata) == BendersCutData
                generatebenderscut(node,cutdata,childindex)
            elseif typeof(cutdata) == LLIntegerCutData
                generateLLintegercut(node,cutdata)
            elseif typeof(cutdata) == IntegerCutData
                generateintegercut(node,cutdata)
            end
            push!(thisitercuts[childindex],cutdata)
        end
        samecuts[childindex] = reduce(*,samecuts[childindex]) && length(samecuts[childindex]) > 0
    end
    setattribute(node,:prevcuts, thisitercuts)
    nodesamecuts = collect(values(samecuts))
    setattribute(node, :stalled, reduce(*,nodesamecuts))
    getattribute(node, :stalled) && @warn("Node $getlabel(node) stalled")
    #if in(node,getattribute(tree, :roots) ) && getattribute(node, :stalled)
    if node == getroot(tree) && getattribute(node, :stalled)
        setattribute(tree, :stalled,  true)
    end
end

function generatebenderscut(node::ModelNode, cd::BendersCutData,index)
    model = getmodel(node)
    θ = getindex(model, :θ)
    x = getattribute(node, :childvars)[index]
    @constraint(model, θ[index] .>= cd.θk + cd.λk'*(cd.xk - x))
end

function bdprepare(tree::ModelTree,lp_solver::AbstractMathProgSolver,node_solver::AbstractMathProgSolver)
    #Check if preprocessing was already done
    if hasattribute(tree,:preprocessed)
        return true
    end

    #Add node attributes
    for node in getnodes(tree)
        setattribute(node,:xin, [])
        setattribute(node,:λ, [])
        setattribute(node,:bound, NaN)
        setattribute(node,:xinvars, [])
        setattribute(node,:preobjval, NaN)
        setattribute(node,:linkconstraints, [])
        setattribute(node,:childvars, Dict(getindex(tree,child) => [] for child in out_neighbors(tree,node)))
        setattribute(node,:cutdata, Dict(getindex(tree,child) => CutData[] for child in out_neighbors(tree,node)))
        setattribute(node,:prevcuts, Dict(getindex(tree,child) => CutData[] for child in out_neighbors(tree,node)))
        setattribute(node,:stalled, false)
    end

    # NOTE: ModelTree handles this.  Could use this for transforming a graph into a tree though
    #identifylevels(graph)

    #Set tree attributes
    setattribute(tree,:numlevels, getnumlevels(tree))  #root node doesn't count as level in ModelTree
    setattribute(tree, :normalized, normalizegraph(tree))
    setattribute(tree, :stalled, false)
    setattribute(tree, :mflat, create_jump_graph_model(tree))
    setattribute(tree, :UB, Inf)
    JuMP.setsolver(getattribute(tree, :mflat),lp_solver)

    links = getlinkconstraints(tree)
    numlinks = length(links)

    for node in getnodes(tree)
        model = getmodel(node)
        if model.solver == JuMP.UnsetSolver()
            model.solver = node_solver
        end
        model.ext[:preobj] = model.obj
        setattribute(node, :cgmodel, deepcopy(model))
        #Add theta to parent nodes
        if out_degree(tree,node) != 0
            childrenindices = [getindex(tree,child) for child in out_neighbors(tree,node)]
            sort!(childrenindices)
            @variable(model, θ[i in childrenindices] >= -1e6)
            model.obj += sum(θ[i] for i in childrenindices)
        end
    end

    #Add dual constraint to child nodes using the linking constraints
    for (numlink,link) in enumerate(links)
        #Take the two variables of the constraint
        var1 = link.terms.vars[1]
        var2 = link.terms.vars[2]
        #Determine which nodes they belong to
        nodeV1 = getnode(var1)
        nodeV2 = getnode(var2)

        #Set the order of the nodes
        if ischildnode(tree,nodeV1,nodeV2)
            childnode = nodeV1
            childvar = var1
            parentnode = nodeV2
            parentvar = var2
        else
            childnode = nodeV2
            childvar = var2
            parentnode = nodeV1
            parentvar = var1
        end
        childindex = getindex(tree,childnode)
        childmodel = getmodel(childnode)
        push!(getattribute(parentnode, :childvars)[childindex],parentvar)
        linkvar = @variable(childmodel)
        setname(linkvar,"linkvar$numlink")
        push!(getattribute(childnode, :xinvars),linkvar)
        conref = @constraint(childmodel, linkvar - childvar == 0)
        push!(getattribute(childnode, :linkconstraints), conref)
    end
    setattribute(tree, :preprocessed, true)
end

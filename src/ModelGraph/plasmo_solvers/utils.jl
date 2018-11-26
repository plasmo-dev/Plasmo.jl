function normalizegraph(graph::AbstractModelGraph)
    n = 1
    for node in getnodes(graph)
        m = getmodel(node)
        if m.objSense == :Max
            m.objSense = :Min
            m.obj = -m.obj
            n = -1
        end
    end
    setattribute(graph, :normalized, n)
    return n
end

function fix(var::JuMP.Variable,value::Real)
    setlowerbound(var,value)
    setupperbound(var,value)
end

"""
Checks if n1 is a child node of n2
"""
ischildnode(tree::ModelTree, n1::ModelNode, n2::ModelNode) = in(n2,in_neighbors(tree,n1))

function savenodeobjective(mf::JuMP.Model)
    g = mf.ext[:Graph]
    numnodes = length(getnodes(g))
    nodeindex = Dict("node$i" => i for i in 1:numnodes)
    nov = mf.ext[:nodeobj] = [AffExpr(0.0) for i in 1:numnodes]
    obj = mf.obj.aff
    for (i,var) in enumerate(obj.vars)
        coeff = obj.coeffs[i]
        varname = mf.colNames[var.col]
        nodename = varname[1:search(varname,'.')-1]
        index = nodeindex[nodename]
        push!(nov[index],coeff,var)
    end
end

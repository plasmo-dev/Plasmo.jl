function interactive(graph,λ,res,lagrangeheuristic)
    α = getattribute(graph , :α)[end]
    n = getattribute(graph , :normalized)
    bound = n*lagrangeheuristic(graph)
    Zk = getattribute(graph , :Zk)[end]
    αexplore(graph,bound)
    plot(0:0.1:2,getattribute(graph , :explore)[end])
    print("α = ")
    α = parse(Float64,readline(STDIN))
    step = α*abs(Zk-bound)/(norm(res)^2)
    λ += step*res
    return λ,bound
end

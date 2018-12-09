# Farmer example from Birge and Louveaux book.

using JuMP
using Plasmo
#using Cbc

NS = 3;                        # number of scenarios
probability = [1/3, 1/3, 1/3]; # probability

CROPS  = 1:3 # set of crops (wheat, corn and sugar beets, resp.)
PURCH  = 1:2 # set of crops to purchase (wheat and corn, resp.)
SELL   = 1:4 # set of crops to sell (wheat, corn, sugar beets under 6K and those over 6K)

Cost     = [150 230 260]   # cost of planting crops
Budget   = 500             # budget capacity
Purchase = [238 210];      # purchase price
Sell     = [170 150 36 10] # selling price
Yield    = [3.0 3.6 24.0;
            2.5 3.0 20.0;
            2.0 2.4 16.0]
Minreq   = [200 240 0]     # minimum crop requirement

# The Plasmo Graph
graph = ModelGraph()

first_stage = Model()

@variable(first_stage, x[i=CROPS] >= 0, Int)
@objective(first_stage, Min, sum(Cost[i] * x[i] for i=CROPS))
@constraint(first_stage, const_budget, sum(x[i] for i = CROPS) <= Budget)

#add the master model to the graph
n1 = add_node(graph,first_stage)
scen_nodes = Array{ModelNode}(NS)
for s in 1:NS
    blk = Model()
    node = add_node(graph,blk)
    scen_nodes[s] = node
    @variable(blk, x[i=CROPS] >= 0, Int)
    @variable(blk, y[j=PURCH] >= 0)
    @variable(blk, w[k=SELL] >= 0)
    #Use this objective to test the extensive form

    #NOTE: don't weight scenario objectives; DSP does that already.  The following line would apply if you were solving with a MPB solver.
    #@objective(blk, Min, (1/NS)*(sum(Purchase[j] * y[j] for j=PURCH) - sum(Sell[k] * w[k] for  k = SELL)))   #MPB objective (Cbc,Gurobi,etc...)
    @objective(blk, Min, sum(Purchase[j] * y[j] for j=PURCH) - sum(Sell[k] * w[k] for  k = SELL))  #DSP objective
    @constraint(blk, const_aux, w[3] <= 6000)

    #TWO WAYS TO DO THIS: Link directly to the first stage in subproblems
    #@linkconstraint(graph, [j=PURCH], Yield[s,j]*first_stage[:x][j] + y[j] - w[j] >= Minreq[j])
    #@linkconstraint(graph, Yield[s,3] * first_stage[:x][3] - w[3] - w[4] >= Minreq[3])

    # OR: duplicate variables and link with non-anticipitivity
    @constraint(blk, [j=PURCH], Yield[s,j]*x[j] + y[j] - w[j] >= Minreq[j])
    @constraint(blk, Yield[s,3] * x[3] - w[3] - w[4] >= Minreq[3])
    @linkconstraint(graph,[i = CROPS],first_stage[:x][i] == blk[:x][i])      #non-anticipitivity constraint
end

dsp_solve(graph,n1,scen_nodes,solve_type = :Benders)  #probabilities are 1/NS by default

@show getvalue(n1[:x])
@show getobjectivevalue(graph)
s = 1
for node in scen_nodes
    println()
    println("scenario $s")
    @show getvalue(node[:x])
    @show getvalue(node[:y])
    @show getvalue(node[:w])
    s += 1
end

#You could also solve extensive form with Gurobi or Cbc.  Just modify the scenario objectives first with probabilities.
#graph.solver = CbcSolver()
#solve(graph)

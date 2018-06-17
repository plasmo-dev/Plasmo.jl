using JuMP
using Gurobi
################################################################################################################################33
#IMPORT DATA TO JULIA WORKSPACE
include("benders_data.jl")
###################################################################################################################
#Function to solve scenario subproblem for a given k and new_capacities; returns the dual variables and optimal objective
function solve_scenario_subproblem(k, new_w)

    #new_w is the solution i.e. the amount of resources available at each base

    #Create the scenario subproblem k
    m_scenario = Model()
    m_scenario.solver = GurobiSolver(OutputFlag = 0)

    #define variables
    @variable(m_scenario, q[B] >= 0) # Amount of resources at base j after all transfers made in first and second stages under scenario k
    @variable(m_scenario, u[F] >= 0) # Unmet demand target in district f under scenario k
    @variable(m_scenario, y[closeArcs] >= 0) # Transfer of resources from bases to close districts under scenario k
    @variable(m_scenario, unmet_target_cost) # Cost of unmet target in scenario k

    @constraint(m_scenario, balance_second_stage_bases[j in B],q[j] + sum(y[a] for a in filter(arc->arc[1]==j, closeArcs)) == new_w[j]) # balance on base j after second stage transfers under scenario k

    @constraint(m_scenario, demand_target[f in F],sum(y[a] for a in filter(arc->arc[2]==f, closeArcs)) + u[f] >= demscens[k,f]) # demand target for each district in all scenarios

    @constraint(m_scenario, cost_unmet_target, unmet_target_cost == sum(costscens[k,f]*u[f] for f in F)) #unmet demand

    @objective(m_scenario, Min, unmet_target_cost)

    #solve the scenario subproblem
    status_scenario = solve(m_scenario)
    #println(status_msck)
    obj_scenario = getobjectivevalue(m_scenario)

    #get dual information
    dual_demand_target = Dict()
    dual_second_stage_balance = Dict()
    for f in F
        dual_demand_target[f] = getdual(getconstraint(m_scenario, :demand_target)[f]);
    end
    for j in B
        dual_second_stage_balance[j] = getdual(getconstraint(m_scenario, :balance_second_stage_bases)[j]);
    end
    return dual_demand_target, dual_second_stage_balance, obj_scenario;
end


########################################################################################################
#MASTER PROBLEM
########################################################################################################
m_master = Model()
m_master.solver = GurobiSolver(OutputFlag = 0)

@variable(m_master, x[baseArcs] >= 0)   # Units of resources moved from base i to base j  (Make this decision 'now')
@variable(m_master, z[B] >= 0)          # Units of resourse purchased at base i
@variable(m_master, w[B] >= 0)          # Amount of resources at base j after all transfers made in first stage ("pass to second stage")
@variable(m_master, first_stage_cost)   # Cost of unmet target in scenario k
@variable(m_master, theta >=0)          # Start cuts

@constraint(m_master, state_budget, sum(costscens[a]*x[a] for a in baseArcs) + sum(h[i]*z[i] for i in B) <= budget) # State Budget constraint

@constraint(m_master, balance_first_stage_bases[j in B], w[j] == init[j] + z[j]
            + sum(x[a] for a in filter(arc->arc[2]==j, baseArcs))
            - sum(x[a] for a in filter(arc->arc[1]==j, baseArcs))) # balance on base j after first stage transfers

@objective(m_master, Min, theta)

##################################################################################################################
tic()

dual_DemandTarget = Dict()
#Now starting the Benders iterations
cutfound = true  ## keep track if any violated cuts were found
iter = 1
while cutfound
    ncuts = 0;
    println("================ Iteration ", iter, " ===================")
    iter = iter+1;
    # Solve current master problem
    cutfound = false;

    status = solve(m_master) #Solved master problem to obtain solution (x_hat_t = new_caps_mpt, theta_hat_t = theta_mpt)

    obj_mpt = getobjectivevalue(m_master)
    lower_bound = obj_mpt;
    println("Current lower bound:", lower_bound)

    x_mpt = getvalue(getvariable(m_master,:x))
    z_mpt = getvalue(getvariable(m_master,:z))
    w_mpt = getvalue(getvariable(m_master,:w))
    theta_mpt = getvalue(getvariable(m_master,:theta))

    #Change the objective function of master problem to include theta variables in objective
    #@objective(m_master, Min, 0 + sum{1/length(S)*theta[k], k in S})

    upper_bound = 0;

    dual_BalanceSecondStageOnBases = Dict()
    dual_DemandTargets =  Dict()
    for k in S
        dual_DemandTarget, dual_BalanceSecondStageOnBase, obj_sck = solve_scenario_subproblem(k,w_mpt)
        for f in F
            dual_DemandTargets[f,k] = dual_DemandTarget[f]
        end
        for j in B
            dual_BalanceSecondStageOnBases[j,k] = dual_BalanceSecondStageOnBase[j]
        end
        upper_bound = upper_bound + (1/length(S)*obj_sck)
    end

    if (theta_mpt - upper_bound < -0.000001)
        @constraint(m_master, benders, theta >= 1/length(S)*sum(w[j]*dual_BalanceSecondStageOnBases[j,k] for j in B,k in S) +
        1/length(S)*sum(demscens[k,f]*dual_DemandTargets[f,k] for f in F, k in S) ) #Benders cuts
        cutfound = true;
        ncuts = ncuts + 1;
    end

    upper_bound = upper_bound + 0;
    println("Current upper bound:", upper_bound)
    #println("Current cuts added:", ncuts)

    if (upper_bound - lower_bound <= 0.000001)
        break;
    end
end
println(toc())

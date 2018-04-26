#Master problem
function create_master()
    m_master = Model()
    m_master.solver = GurobiSolver(OutputFlag = 0)

    @variable(m_master, x[baseArcs] >= 0)   # Units of resources moved from base i to base j  (Make this decision 'now')
    @variable(m_master, z[B] >= 0)          # Units of resourse purchased at base i
    @variable(m_master, w[B] >= 0)          # Amount of resources at base j after all transfers made in first stage ("pass to second stage")
    @variable(m_master, first_stage_cost)   # Cost of unmet target in scenario k
    @variable(m_master, theta >=0)          # Start cuts

    @constraint(m_master, state_budget, sum(cost[a]*x[a] for a in baseArcs) + sum(h[i]*z[i] for i in B) <= budget) # State Budget constraint

    @constraint(m_master, balance_first_stage_bases[j in B], w[j] == init[j] + z[j]
                + sum(x[a] for a in filter(arc->arc[2]==j, baseArcs))
                - sum(x[a] for a in filter(arc->arc[1]==j, baseArcs))) # balance on base j after first stage transfers

    @objective(m_master, Min, theta)

    return m_master
end

#Function to solve scenario subproblem for a given k and new_capacities; returns the dual variables and optimal objective
function create_scenario_subproblem(new_w,demand,cost)
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
end

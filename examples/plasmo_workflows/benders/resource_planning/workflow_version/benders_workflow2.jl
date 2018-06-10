###############################################################
#Benders example
##############################################################
function update_duals(workflow::Workflow,node::DispatchNode,sub_result::Attribute,scenario::Attribute)
    model = node[:model]
    scenarios = node[:scenarios]

    #Get updated dual values and objective
    sub_result = getvalue(node,:sub_result)
    duals = sub_result[:duals]
    sub_objective = sub_result[:objective]

    push!(node[:dual_updates],duals) #push the dual value of the last attribute update
    push!(node[:objective_updates],objective)

    n_updates = length(node[:dual_updates])
    #If all the dual updates are finished
    if n_updates == length(scenarios)
        #Create the single - cut based on all updates and schedule to solve the master problem
        theta = model[:theta]
        S = length(scenarios)
        upper_bound = 1/S*sum(obj for obj in node[:objective_updates])
        setattribute(node,:upper_bound,upper_bound)
        w = model[:w]
        duals = node[:dual_updates]
        dual_demand = duals[:demand]    #all of the dual attributes
        dual_balance = duals[:balance]  #all of the dual attributes
        if (getvalue(theta) - upper_bound < -0.000001)
            w = getvariable(model,:w)
            @constraint(model, benderscut, theta >= 1/S*sum(w[j]*dual_balance[s][b] for s in scenarios,b in Bases)
                                        + 1/S*sum(s[:demands][f]*dual_demand[s][f] for s in scenarios, f in Facilities))
        end
        #Schedule the solve action
        schedulesignal(workflow,node,(:execute,node[:solve_master]),0.0)
        node[:dual_updates] = []
        node[:objective_updates] = []

    else #Need to send out a new scenario
        scenarios_out = node[:scenarios_out]
        if scenarious_out < length(scenarios)
            updateattribute(scenario,scenarios[scenarious_out + 1])  #The next scenario to send out
            node[:scenarios_out] += 1
        end
    end

    return true
end


function solve_master(node::DispatchNode)
    model = node[:model]
    tic()
    solve(model)
    solve_time = toc()
    setnodecomputetime(node,solve_time)
    updateattribute(node,:solution,getvalue(model[:w]))
    setattribute(node,:lower_bound,getobjectivevalue(model))

    #Send out scenarios
    scenarios = node[:scenarios]
    i = 1
    for scenario_channel in node[:scenario_channels]
        updateattribute(scenario_channel,scenarios[i])
        i += 1
    end
    setattribute(node[:scenarios_out],i)

    return true
end


function solve_subproblem(node::DispatchNode)
    new_w = getvalue(node[:solution])
    scenario = getvalue(node[:scenario])
    demands = scenario[:demands]
    costs = scenario[:costs]

    m_scenario = create_scenario_subproblem(new_w,demands,costs)

    tic()
    status_scenario = solve(m_scenario)
    solve_time = toc()
    setnodecomputetime(node,solve_time)

    obj_scenario = getobjectivevalue(m_scenario)

    dual_demand_target = getdual(m_scenario,:demand_target)
    dual_second_stage_balance = getdual(m_scenario,:second_stage_balance)
    duals = Dict(:demand => dual_demand_target,:balance => dual_second_stage_balance)
    sub_result = Dict(:duals => duals,:objective => obj_scenario)

    updateattribute(node,:sub_result,sub_result)

    return true
end

#Create the workflow
workflow = Workflow()
#set_terminate(workflow,check_terminate)
master_node = add_dispatch_node!(workflow)
setattribute(master_node,:model,create_master()) #the master model
setattribute(master_node,:scenarios_out,0)      #how many scenarios have been sent
setattribute(master_node,:scenarios,scenarios)   #set of scenarios

master_duals = setattribute(master_node,:dual_attributes,[])  #Array of the dual attributes to receive
setattribute(master_node,:dual_updates,[])                    #Array of all dual updates received

#solution attribute gets communicated
@attribute(master_node,solution)  #master node's current solution to pass to sub nodes
@action(master_node, run_master, args = master_node) #triggered_by = ....   #Give attribute updates that will trigger the action.  Sets up transition.
schedulesignal(workflow,(:execute,master_node[:run_master]),0.0)  #figures out the target from the action

#Assume we have 3 processors to do subproblems
n_subnodes = 3
for i = 1:n_subnodes
    #Create each subnode
    sub_node = add_dispatch_node!(workflow)     #An agent that can run computations
    @attribute(sub_node, solution)              #An attribute with local and global values
    @attribute(sub_node, scenario)
    @attribute(sub_node, sub_result)

    #Receiving an update to the scenario will trigger this action
    subnode_action = @action(subnode, solve_subproblem, args = subnode, triggered_by = scenario, schedule_delay = 0)  #Signal = (execute run_subproblem)
    @attribute(sub_node,duals)

    #Add sub node attributes
    scenario = @attribute(master_node)    #scenario channel on master
    master_sub = @attribute(master_node) #dual channel on master

    #master_dual updates the master dual information and possibly passes a scenario back
    @action(master_node, update_duals,args = (workflow,master_node,master_dual,scenario), triggered_by = master_dual)
    push!(master_duals,master_dual)         #Keep an array of all the dual attributes on the master

    #Connect the master attribute to the subnode attribute.  If the master attribute updates, it will send the result after synchronization
    c1 = @connect(workflow, master_node[:solution] => sub_node[:solution], delay = 0)  #no action
    c2 = @connect(workflow, scenario => sub_node[:scenario], delay = 0)                #action = solve_subproblem
    @connect(workflow, sub_node[:sub_result] => master_sub)                          #action = update_duals

    setpriority(workflow,c1,c2)  #A solution will communicate before a scenario if they happen at the same time
end

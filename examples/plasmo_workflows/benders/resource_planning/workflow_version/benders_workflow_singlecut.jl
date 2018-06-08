using JuMP
using Gurobi
using Plasmo.Workflows

# Benders Single Cut
# NOTE:  All scenarios must complete to generate a cut (potential bottleneck)

#Import problem data
#TODO Modify for workflow
include("resource_data.jl")
include("resource_model.jl")

###################################################################################################################
function run_master(node::DispatchNode)

    #NOTE Action paradigm should replace this
    lastupdate = getlastreceivedattribute(node)  #Get the latest updated attribute.  Should be a dual value from a subproblem

    #First execution
    first_run = (lastupdate == nothing)
    if first_run == false
        #Update scenarios that were completed
        scenarios_completed = getattribute(node,:scenarios_complete) + 1
        setattribute(node,:scenarios_complete,scenarios_completed)
    else
        scenarios_completed = 0
    end

    add_cut = false
    #Check how many scenarios have been completed
    scenarios_completed < n_scenarios? solve_master = false : (solve_master = true ; add_cut = true)
    #If enough scenarios are done, or if it's the first run.  Solve the master.  Then send out new scenarios to everyone.
    if solve_master == true || first_run == true
        #SOLVE MASTER PROBLEM
        model = getattribute(node,:model)
        scenarios = getattribute(node,:scenarios)
        #Get updated dual values
        #duals = getvalue(getworkflowattribute(node,:duals))
        duals = getworkflowattribute(node,:duals) #Dictionary of labels to attributes

        dual_demand = duals[:demand]    #all of the dual attributes
        dual_balance = duals[:balance]  #all of the dual attributes
        S = length(scenarios)

        #Create the single - cut based on all updates
        if add_cut == true
            theta = model[:theta]
            #Single benders cut
            w = getvariable(model,:w)

            @constraint(model, benderscut, theta >= 1/S*sum(w[j]*dual_balance[s][b] for s in scenarios,b in Bases)
                                        + 1/S*sum(s[:demands][f]*dual_demand[s][f] for s in scenarios, f in Facilities))
        end

        tic()
        solve(model)
        solve_time = toc()
        setnodecomputetime(node,solve_time)
        setworkflowattribute(node,:solution,getvalue(model[:w]))

        #SEND NEW SCENARIOS
        i = 1
        for scenario in getworkflowattribute(node,:scenario_channels)
            setworkflowattribute(node,scenario,scenarios[i])
            i += 1
        end
        #Update scenarios that were sent
        setattribute(node,:scenarios_sent, i)
        return true  #scenarios were updated on completion

    else
        #Pass a new scenario to the node that completed if there's a scenario available
        scenario_out = scenario_map[lastupdate]     #map of updated dual to scenario that should get updated
        setworkflowattribute(node,scenario_out,new_scenario)

        scenarios_sent = getattribute(node,:scenarios_sent)
        setattribute(node,:scenarios_sent,scenarios_sent + 1)

        return true
    end
end

function solve_subproblem(node::DispatchNode)
    new_w = getvalue(getworkflowattribute(node,:w))

    scenario = getvalue(getworkflowattribute(node,:scenario))
    demands = scenario[:demands]
    costs = scenario[:costs]

    m_scenario = create_scenario_subproblem(new_w,demands,costs)

    tic()
    status_scenario = solve(m_scenario)
    solve_time = toc()
    setnodecomputetime(node,solve_time)

    obj_scenario = getobjectivevalue(m_scenario)

    dual_demand_target = getdual(m_scenario,:demand_target);
    dual_second_stage_balance = getdual(m_scenario,:second_stage_balance);
    duals = Dict(:demand => dual_demand_target,:balance => dual_second_stage_balance)
    setworkflowattribute(node,:duals,duals)
end

#Create the workflow
workflow = Workflow()
master_node = add_dispatch_node!(workflow)
addattribute!(master_node,:model,create_master()) #the master model
addattribute!(master_node,:scenarios_sent,0)      #how many scenarios have been sent
addattribute!(master_node,:scenarios_complete,0)  #how many scenarios have been completed
addattribute!(master_node,:scenarios,scenarios)   #set of scenarios
addattribute!(master_node,:scenario_map,Dict())   #map dual attributes to scenario attributes
master_duals = addattribute!(master_node,:duals,[])

#solution attribute gets communicated
addworkflowattribute!(master_node,:solution)  #master node's current solution to pass to sub nodes

#NOTE Tasks might become general actions
set_node_function(master_node,run_master)
set_node_function_arguments(master_node,[master_node])
schedulesignal(workflow,:execute,master_node,0.0)

#Assume we have 3 processors to do subproblems
n_subnodes = 3
for i = 1:n_subnodes
    #Create the subnode
    sub_node = add_dispatch_node!(workflow)
    set_node_function(sub_node,run_subproblem)
    set_node_function_arguments(sub_node1,[sub_node])

    #Add sub node attributes
    addworkflowattribute!(sub_node,:duals)
    addworkflowattribute!(sub_node,:solution,execute_on_receive = false)

    #Add new master node attributes which we will connect
    master_scenario = addworkflowattribute!(master_node,Symbol("scenario_to_$i"))
    master_dual = addworkflowattribute!(master_node,Symbol("duals$i"))
    master_node[:scenario_map][master_dual] = master_scenario

    push!(master_duals,master_dual) #create array of master dual solutions

    #Make connections
    c1 = connect!(workflow,sub_node[:duals],master_dual)               #action = run_master             #connect dual value to master
    c2 = connect!(workflow,master_scenario,sub_node[:scenario])        #action = solve_subproblem       #connect master scenario to subproblem
    c3 = connect!(workflow,master_node[:solution],sub_node[:solution]) #no action                       #connect master solution to sub problem

    #setcommunicateorder(workflow,c3,c2)  #c3 will communicate before c2 if they trigger at the same time

end

# @action node (attribute_received,x) begin
#    println(x)
# end

# @action node (comm_sent,x)
# end

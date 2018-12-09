using JuMP
using Gurobi
using Plasmo.PlasmoWorkflows

#NOTE: This is an old version of the benders simulation before I realized that dispatch nodes need to have multiple tasks
#NOTE: This example will not work.


#Import problem data
#TODO Modify for workflow
include("resource_data.jl")
include("resource_model.jl")

###################################################################################################################
#Master task runs through a lot of logic.  Might try a pure action based approach to split this up.
function run_master(node::DispatchNode)
    #NOTE Action paradigm should replace this
    lastupdate = getlastreceivedattribute(node)  #Get the latest updated attribute.  Should be a dual value from a subproblem

    #First execution
    first_run = (lastupdate == nothing)
    if first_run == false
        #Update scenarios that were completed
        scenarios_completed = getattribute(node,:scenarios_complete) + 1
        setattribute(node,:scenarios_complete,scenarios_completed)
        push!(getattribute(node,:dual_updates),getvalue(lastupdate)[:duals]) #push the dual value of the last attribute update
        push!(getattribute(node,:objective_updates),getvalue(lastupdate)[:objectives])
    else
        scenarios_completed = 0
    end

    add_cut = false
    #Check how many scenarios have been completed
    scenarios_completed < n_scenarios? solve_master = false : (solve_master = true ; add_cut = true)
    #If enough scenarios are done, or if it's the first run.  Solve the master.  Then send out new scenarios to everyone.
    scenarios = getattribute(node,:scenarios)
    if solve_master == true || first_run == true
        #SOLVE MASTER PROBLEM
        model = getattribute(node,:model)

        #Get updated dual values
        duals = getvalue(getworkflowattribute(node,:duals))
        dual_demand = duals[:demand]    #all of the dual attributes
        dual_balance = duals[:balance]  #all of the dual attributes
        S = length(scenarios)

        #Create the single - cut based on all updates
        if add_cut == true
            theta = model[:theta]
            if (getvalue(theta) - upper_bound < -0.000001)
                w = getvariable(model,:w)

                @constraint(model, benderscut, theta >= 1/S*sum(w[j]*dual_balance[s][b] for s in scenarios,b in Bases)
                                            + 1/S*sum(s[:demands][f]*dual_demand[s][f] for s in scenarios, f in Facilities))
            end
        end

        tic()
        solve(model)
        solve_time = toc()

        setnodecomputetime(node,solve_time)
        setworkflowattribute(node,:solution,getvalue(model[:w]))
        setattribute(node,:lower_bound,getobjectivevalue(model))
        setattribute(node,:upper_bound,1/S*sum(obj for obj in node[:objective_updates]))

        setattribute(node,:dual_updates,[]) #reset dual information
        setattribute(node,:objective_updates,[])
        #START SENDING NEW SCENARIOS
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
        scenario_out_attribute = scenario_map[lastupdate]     #map of updated dual to scenario that should get updated
        new_scenario = scenarios[scenarios_completed + 1]
        setworkflowattribute(node,scenario_out_attribute,new_scenario)
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

    dual_demand_target = getdual(m_scenario,:demand_target)
    dual_second_stage_balance = getdual(m_scenario,:second_stage_balance)
    duals = Dict(:demand => dual_demand_target,:balance => dual_second_stage_balance)
    sub_result = Dict(:duals => duals,:objective => obj_scenario)

    setworkflowattribute(node,:sub_result,sub_result)
end

#Termination function for the workflow to check
function check_terminate()
    lower = getattribute(master_node,:lower_bound)
    upper = getattribute(master_node,:upper_bound)
    if upper_bound - lower_bound <= 0.000001
        return true
    else
        return false
    end
end

#Create the workflow
workflow = Workflow()
#set_terminate(workflow,check_terminate)
master_node = add_dispatch_node!(workflow)
addworkflowattribute!(master_node,:model,create_master()) #the master model
setattribute(master_node,:scenarios_sent,0)      #how many scenarios have been sent
setattribute(master_node,:scenarios_complete,0)  #how many scenarios have been completed
setattribute(master_node,:scenarios,scenarios)   #set of scenarios
setattribute(master_node,:scenario_map,Dict())   #map dual attributes to scenario attributes
master_duals = setattribute(master_node,:dual_attributes,[])
setattribute(master_node,:dual_updates,[])

#solution attribute gets communicated
addworkflowattribute!(master_node,:solution)  #master node's current solution to pass to sub nodes

#NOTE Tasks might become general actions
set_node_function(master_node,run_master)
set_node_function_arguments(master_node,[master_node])
schedulesignal(workflow,:execute,master_node,0.0)

#Assume we have 3 processors to do subproblems
n_subnodes = 3
for i = 1:n_subnodes
    #Create each subnode
    sub_node = add_dispatch_node!(workflow)
    set_node_function(sub_node,run_subproblem)
    set_node_function_arguments(sub_node1,[sub_node])

    #Add sub node attributes
    addworkflowattribute!(sub_node,:duals)
    addworkflowattribute!(sub_node,:solution,execute_on_receive = false)

    #Add new master node attributes which we will connect
    master_scenario = addworkflowattribute!(master_node,Symbol("scenario_to_$i"))
    master_dual = addworkflowattribute!(master_node,Symbol("duals$i"))
    master_node[:scenario_map][master_dual] = master_scenario  #map received dual attribute to a scenario attribute

    push!(master_duals,master_dual) #create array of master dual solutions

    #Make connections
    c1 = connect!(workflow,sub_node[:duals],master_dual)               #action = run_master             #connect dual value to master
    c2 = connect!(workflow,master_scenario,sub_node[:scenario])        #action = solve_subproblem       #connect master scenario to subproblem
    c3 = connect!(workflow,master_node[:solution],sub_node[:solution]) #no action                       #connect master solution to sub problem

    setcommunicateorder(workflow,c3,c2)  #c3 will communicate before c2 if they trigger at the same time

end

using Plasmo.PlasmoWorkflows
using Plasmo.PlasmoGraphBase
using JuMP
using Gurobi

include("resource_data.jl")
include("resource_model.jl")


###############################################################
#Benders example
##############################################################
function update_duals(workflow::Workflow,node::DispatchNode,sub_result::Attribute,scenario::Attribute)
    #Get node data
    tic()
    model = node[:model]
    scenarios = node[:scenarios]

    #Get updated dual values and objective
    sub_result = getlocalvalue(sub_result)
    duals = sub_result[:duals]
    sub_objective = sub_result[:objective]

    #Modify node data
    println("Adding update")
    push!(node[:dual_updates],duals) #push the dual value of the last attribute update
    push!(node[:objective_updates],sub_objective)

    n_updates = length(node[:dual_updates])
    #If all the dual updates are finished
    if n_updates == length(scenarios)
        println("Adding Cut")
        #Create the single cut based on all updates and schedule the master problem
        theta = model[:theta]
        S = length(scenarios)
        upper_bound = 1/S*sum(obj for obj in node[:objective_updates])
        setattribute(node,:upper_bound,upper_bound)
        duals = node[:dual_updates]
        if (JuMP.getvalue(theta) - upper_bound < -0.000001)
            w = model[:w]
            @constraint(model, benderscut, theta >= 1/S*sum(w[b]*duals[s][:balance][b] for s in 1:S,b in Bases)
                                        + 1/S*sum(scenarios[s][:demands][f]*duals[s][:demand][f] for s in 1:S, f in Facilities))
        end
        #Schedule the solve action

        task = node.node_tasks[:run_master_problem]
        schedulesignal(workflow,Signal(:execute,task),node,getcurrenttime(workflow))
        @show getqueue(workflow)
        #scheduleexecute(workflow,getnodetask(node,:solve_master),0.0)
        setattribute(node,:dual_updates,[])
        setattribute(node,:objective_updates,[])
    else #Need to send out a new scenario
        scenarios_out = node[:scenarios_out]
        if scenarios_out < length(scenarios)
            updateattribute(scenario,scenarios[scenarios_out + 1])  #The next scenario to send out
            setattribute(node,:scenarios_out,scenarios_out + 1)
        end
    end
    solve_time = toc()
    #Actions can have pre-defined labels
    #setnodecomputetime(node,(:update_dual,sub_result),1.0)
    return true
end


function solve_master(node::DispatchNode)
    tic()
    model = node[:model]

    solve(model)


    updateattribute(node[:solution],JuMP.getvalue(model[:w]))
    setattribute(node,:lower_bound,getobjectivevalue(model))

    #Send out scenarios
    scenarios = node[:scenarios]
    i = 0
    for scenario_channel in node[:scenario_channels]
        updateattribute(scenario_channel,scenarios[i+1])
        i += 1
    end
    setattribute(node,:scenarios_out,i)

    #Convergence check
    lower_bound = master_node[:lower_bound]
    upper_bound = master_node[:upper_bound]



    if upper_bound - lower_bound <= 0.000001
        return StopWorkflow("Converged")
    else
        solve_time = toc()
        setcomputetime(getnodetask(node,:run_master_problem),solve_time)
        return true
    end
end


function solve_subproblem(node::DispatchNode)
    tic()
    println("Solving sub-problem")
    #Get attribute values
    new_w = getlocalvalue(node[:solution])
    scenario = getlocalvalue(node[:scenario])
    demands = scenario[:demands]
    costs = scenario[:costs]

    #Create a subproblem based on the data
    m_scenario = create_scenario_subproblem(new_w,demands,costs)


    status_scenario = solve(m_scenario)

    #setnodecomputetime(node,solve_time)
    #Set the compute time for the :solve_subproblem action
    #TODO Make sure I grab the right task here


    #Get the objective value and dual variables
    obj_scenario = getobjectivevalue(m_scenario)
    dual_demand_target = getdual(m_scenario[:demand_target])
    dual_second_stage_balance = getdual(m_scenario[:second_stage_balance])

    duals = Dict(:demand => dual_demand_target,:balance => dual_second_stage_balance)
    sub_result = Dict(:duals => duals,:objective => obj_scenario)
    #Update the sub_result attribute.  This will be sent to the master.
    updateattribute(node[:sub_result],sub_result)
    solve_time = toc()
    setcomputetime(getnodetask(node,:solve_subproblem),solve_time)
    return true
end

#Create the workflow
workflow = Workflow()
#set_terminate(workflow,check_terminate)
master_node = add_dispatch_node!(workflow)
setattribute(master_node,:model,create_master()) #the master model
setattribute(master_node,:scenarios_out,0)       #how many scenarios have been sent
setattribute(master_node,:scenarios,scenarios)   #set of scenarios to dish out
setattribute(master_node,:upper_bound,10000)

master_duals = setattribute(master_node,:dual_attributes,[])  #Array of the dual attributes to receive
master_scenarios = setattribute(master_node,:scenario_channels,[])  #Array of the dual attributes to receive
setattribute(master_node,:dual_updates,[])                    #Array of all dual updates received
setattribute(master_node,:objective_updates,[])

#solution attribute gets communicated
addworkflowattribute!(master_node,:solution)  #master node's current solution to pass to sub nodes
task = addnodetask!(workflow,master_node,:run_master_problem,solve_master,args = [master_node])
#@nodetask(master_node,run_master_node,run_master(master_node)) #triggered_by = ....   #Give attribute updates that will trigger the action.  Sets up transition.

#Initialize the workflow
schedulesignal(workflow,Signal(:execute,task),master_node,0.0)

#Assume we have 3 processors to do subproblems
n_subnodes = 3
for i = 1:n_subnodes
    #Create each subnode
    sub_node = add_dispatch_node!(workflow)     #An agent that can run computations
    addworkflowattribute!(sub_node,:solution)
    scenario = addworkflowattribute!(sub_node,:scenario)
    addworkflowattribute!(sub_node,:sub_result)
    #@attribute(sub_node, solution)              #An attribute with local and global values
    #@attribute(sub_node, scenario)
    #@attribute(sub_node, sub_result)

    #Receiving an update to the scenario will trigger this action
    #subnode_action = @nodetask(subnode,solve_subproblem(subnode), triggered_by = scenario)  #Signal = (execute run_subproblem)
    subnode_action = addnodetask!(workflow,sub_node,:solve_subproblem,solve_subproblem, args = [sub_node], triggered_by_attributes = [scenario]) #task is triggered by an update to the scenario attribute

    #Add attributes to master for each subnode
    # scenario = @attribute(master_node)    #scenario channel on master
    # master_sub = @attribute(master_node)  #dual channel on master

    #NOTE Do something like create indices of attributes before the loop
    master_scenario = addworkflowattribute!(master_node,Symbol(string("scenario$i")))
    master_sub = addworkflowattribute!(master_node,:master_result_from_sub)

    #Create a different node task for each subnode update
    #@nodetask(master_node, update_duals(workflow,master_node,master_sub,scenario), triggered_by_attributes = [master_sub])  #Creates transition on master_node.  Triggered by receiving the master_sub attribute
    addnodetask!(workflow,master_node,:update_duals,update_duals,args = [workflow,master_node,master_sub,master_scenario], triggered_by_attributes = [master_sub])

    push!(master_duals,master_sub)        #Keep an array of all the dual attributes on the master
    push!(master_scenarios,master_scenario)

    # #Connect the master attribute to the subnode attribute.  If the master attribute updates, it will send the result after synchronization
    # c1 = @connect(workflow, master_node[:solution] => sub_node[:solution], comm_delay = 0)  #no action taken
    # c2 = @connect(workflow, scenario => sub_node[:scenario], comm_delay = 0)                #action = solve_subproblem
    # @connect(workflow, sub_node[:sub_result] => master_sub, comm_delay = 0)                 #action = update_duals

    c1 = connect!(workflow, master_node[:solution], sub_node[:solution], comm_delay = 0)    #no action taken
    c2 = connect!(workflow, master_scenario, sub_node[:scenario], comm_delay = 0)                #action = solve_subproblem
    connect!(workflow, sub_node[:sub_result], master_sub, comm_delay = rand())


    #Maintain a priority mapping (This is a fairly standard practice)
    #setpriority(workflow,c1,0)  #custom priority on channel
    #setpriority(workflow,c1,c2)  #A solution will communicate before a scenario if they happen at the same time
end

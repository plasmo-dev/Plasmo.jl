using Plasmo.PlasmoWorkflows
using Plasmo.PlasmoGraphBase
using JuMP

include("resource_data.jl")
include("resource_model.jl")

###############################################################
#Benders example
##############################################################aa
#Arguments: Workflow, dispatch node, the subnode result attribute, a corresponding master node scenario attribute.  (sub node sends a result, master node updates a scenario to send back to that node)
function update_duals(workflow::Workflow,node::DispatchNode,sub_result::Attribute,scenario::Attribute)
    #Get the master model
    model = node[:model]
    scenarios = node[:scenarios]   #The set of scenarios

    #Get updated dual values and objective
    sub_result = getlocalvalue(sub_result)    #attributes have local and global values.  you generally should use getlocalvalue when accessing attributes.
    duals = sub_result[:duals]                  #the sub result has duals
    sub_objective = sub_result[:objective]      #the sub result also has the sub node's objective value

    scenario_id = sub_result[:scenario_id]  #should be an id
    node[:dual_updates][scenario_id] = duals
    #Modify node data #NOTE: Fix this
    #push!(node[:dual_updates],duals) #push the dual value of the last attribute update

    push!(node[:objective_updates],sub_objective)

    n_updates = length(node[:dual_updates])

    #If all the dual updates are finished (i.e. all the scenarios came back)
    if n_updates == length(scenarios)
        #Create the single cut based on all updates and schedule the master problem
        println("Adding Single Cut")
        theta = model[:theta]
        #S = length(scenarios)
        upper_bound = 1/length(S)*sum(obj for obj in node[:objective_updates])
        setattribute(node,:upper_bound,upper_bound)
        duals = node[:dual_updates]

        if (JuMP.getvalue(theta) - upper_bound < -0.000001)
            w = model[:w]

            #NOTE: scenarios[s] and duals[s] may not actually correspond!
            benderscut = @constraint(model, theta >= 1/length(S)*sum(w[b]*duals[s][:balance][b] for s in S,b in Bases)
                                        + 1/length(S)*sum(scenarios[s][:demands][f]*duals[s][:demand][f] for s in S, f in Facilities))
            println(benderscut)
        end

        #Added the cut, now schedule another solve
        task = node.node_tasks[:run_master_problem]
        schedulesignal(workflow,Signal(:execute,task),node,getcurrenttime(workflow))
        #setattribute(node,:dual_updates,[])
        setattribute(node,:dual_updates,Dict())
        setattribute(node,:objective_updates,[])
    else #Need to send out a new scenario
        scenarios_out = node[:scenarios_out]
        if scenarios_out < length(scenarios)
            updateattribute(scenario,scenarios["S$(scenarios_out)"])  #The next scenario to send out.  Use updateattribute to update a workflow attribute
            setattribute(node,:scenarios_out,scenarios_out + 1)
        end
    end
    return true
end


function solve_master(node::DispatchNode)
    tic()
    model = node[:model]
    solve(model)
    updateattribute(node[:solution],JuMP.getvalue(model[:w]))
    setattribute(node,:lower_bound,getobjectivevalue(model))

    #Start sending out scenarios.  Each scenario channel will trigger communication to a sub node.
    scenarios = node[:scenarios]
    i = 0
    for scenario_channel in node[:scenario_channels]
        updateattribute(scenario_channel,scenarios["S$(i)"])
        i += 1
    end
    setattribute(node,:scenarios_out,i)

    #Convergence check
    lower_bound = master_node[:lower_bound]
    upper_bound = master_node[:upper_bound]
    println("current lower bound: ",lower_bound)
    println("current upper bound: ", upper_bound)
    if upper_bound - lower_bound <= 0.000001
        throw(StopWorkflow("Converged"))  #NOTE: I don't deal with this return result yet
    else
        solve_time = toc()
        setcomputetime(getnodetask(node,:run_master_problem),solve_time)
        return true
    end
end


function solve_subproblem(node::DispatchNode)

    #Get attribute values
    new_w = getlocalvalue(node[:solution])   #Current solution
    #println(new_w)
    scenario = getlocalvalue(node[:scenario])
    demands = scenario[:demands]
    costs = scenario[:costs]

    #Create a subproblem based on the data
    m_scenario = create_scenario_subproblem(new_w,demands,costs)
    tic()
    status_scenario = solve(m_scenario)
    solve_time = toc()

    #Get the objective value and dual variables
    obj_scenario = getobjectivevalue(m_scenario)

    dual_demand_target = getdual(m_scenario[:demand_target])
    dual_second_stage_balance = getdual(m_scenario[:second_stage_balance])
    println("sub objective: ", obj_scenario)
    println("sub dual 1: ", sum(dual_demand_target))
    println("sub dual 2: ", sum(dual_second_stage_balance))

    duals = Dict(:demand => dual_demand_target,:balance => dual_second_stage_balance)
    sub_result = Dict(:duals => duals,:objective => obj_scenario, :scenario_id => scenario[:id])

    #Update the sub_result attribute.  This will be sent to the master.
    updateattribute(node[:sub_result],sub_result)

    #Set the compute time manually.  This will make the node "complete" after this amount of time.
    setcomputetime(getnodetask(node,:solve_subproblem),solve_time)
    return true
end

#Create the workflow
tic()
workflow = Workflow()

#Add a compute node to run the master problem
master_node = add_dispatch_node!(workflow)


#Add simple attributes.  This is just data
setattribute(master_node,:model,create_master())        #the master model
setattribute(master_node,:scenarios_out,0)              #how many scenarios have been sent out
setattribute(master_node,:scenarios,scenarios)          #set of scenarios to dish out
setattribute(master_node,:upper_bound,10000)            #The current upper bound

master_duals = setattribute(master_node,:dual_attributes,[])            #Array of the dual attributes to receive
master_scenarios = setattribute(master_node,:scenario_channels,[])      #Array of the dual attributes to receive
#setattribute(master_node,:dual_updates,[])                              #Array of all dual updates received
setattribute(master_node,:dual_updates,Dict())
setattribute(master_node,:objective_updates,[])

#A workflow attribute is data that gets communicated to other nodes.  Workflow attributes can be connected to other node attributes
#Here, the solution attribute will be communicated.
addworkflowattribute!(master_node,:solution)  #master node's current solution to pass to sub nodes

#Add a task to the master node.  arguments are: (workflow,node,task_label,function,function_arguments)
task = addnodetask!(workflow,master_node,:run_master_problem,solve_master,args = [master_node])

#Initialize the workflow.  To do so, we will schedule a signal to execute the master task at time 0
schedulesignal(workflow,Signal(:execute,task),master_node,0.0)  #schedule an execute signal on the master node at time 0

#Assume we have 3 processors to do subproblems (note: Could try more)
channels = []
sub_nodes = []
n_subnodes = 7
for i = 1:n_subnodes
    #Create each sub compute node
    sub_node = add_dispatch_node!(workflow)
    addworkflowattribute!(sub_node,:solution)               #sub node will receive a solution
    scenario = addworkflowattribute!(sub_node,:scenario)    #sub node has a scenario
    addworkflowattribute!(sub_node,:sub_result)             #sub node will produce a result

    #Receiving an update to the scenario will trigger this action because triggered_by_attributes is the scenario.
    subnode_action = addnodetask!(workflow,sub_node,:solve_subproblem,solve_subproblem, args = [sub_node], triggered_by_attributes = [scenario])    #task is triggered by an update to the scenario attribute

    #Now add corresponding attributes to the master node.
    master_scenario = addworkflowattribute!(master_node,Symbol(string("scenario$i")))  #This adds a scenario attribute to the master for each subnode.  The master node has a scenario attribute for each sub node connected to it.
    master_sub = addworkflowattribute!(master_node,:master_result_from_sub)            #Master node has an attribute for each sub node's result

    #Create a different node task for each subnode update
    addnodetask!(workflow,master_node,:update_duals,update_duals,args = [workflow,master_node,master_sub,master_scenario], triggered_by_attributes = [master_sub])

    push!(master_duals,master_sub)              #Keep an array of all the dual workflow attributes on the master for easy access
    push!(master_scenarios,master_scenario)     #Keep an array of the scenario attributes on the master for easy access

    #Make the connections
    #NOTE: If the solution takes longer than the scenario to show up, this won't work.  I'm thinking of including something like guards and conditions, but I think that gets kind of messy.
    c1 = connect!(workflow, master_node[:solution], sub_node[:solution], comm_delay = 0.0)    #no action taken is taken when a solution is communicated.  That's because the sub node isn't triggered by an updated solution.
    c2 = connect!(workflow, master_scenario, sub_node[:scenario], comm_delay = 0.0)        #action = solve_subproblem
    c3 = connect!(workflow, sub_node[:sub_result], master_sub, comm_delay = 0.0)

    append!(channels,[c1,c2,c3])
    push!(sub_nodes,sub_node)
    #Maintain a priority mapping (This is a fairly standard practice)
    #setpriority(workflow,c1,0)  #custom priority on channel
end


execute!(workflow)
println(toc())

println("workflow completed in: ",getcurrenttime(workflow))
println(master_node[:upper_bound])
println(master_node[:lower_bound])

#OR to see what's happening...
#step(workflow)
#getqueue(workflow)
#step(workflow)
# ....

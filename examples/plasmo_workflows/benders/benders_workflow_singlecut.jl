using JuMP
using Gurobi
using PlasmoWorkflows

# Benders Single Cut
# NOTE:  All scenarios must complete to generate a cut (potential bottleneck)

#Import problem data
include("benders_data.jl")
###################################################################################################################

function solve_master(workflow::Workflow,node::DispatchNode)
    model = getattribute(node,:model)

    triggered_by = gettriggeredby(node)
    duals = getinput(node,:duals) #This

    #Create the single - cut
    @constraint(model,)
    solve(model)  #model state is updated
    w = getvalue(model[:w])  #solution to send to subproblem

    setouput(node,:w,w)  #outputs will communicate

    #return w  #will set default output
end

function solve_subproblem(node::DispatchNode)
    new_w = getinput(node,:w)
    demand = getinput(node,:demand)
    cost = getinput(node,:cost)


    m_scenario = create_scenario_subproblem(new_w,demand,cost)

    status_scenario = solve(m_scenario)
    obj_scenario = getobjectivevalue(m_scenario)

    #get dual information
    dual_demand_target = Dict()
    dual_second_stage_balance = Dict()
    for f in F
        dual_demand_target[f] = getdual(getindex(m_scenario, :demand_target)[f]);
    end
    for j in B
        dual_second_stage_balance[j] = getdual(getindex(m_scenario, :balance_second_stage_bases)[j]);
    end
    return dual_demand_target, dual_second_stage_balance, obj_scenario;
end

n_subnodes = 3
workflow = Workflow()

master_node = add_dispatch_node!(workflow)
@nodeattributes(masternode,model = create_master(),scenario_data = Array())
@inputs(masternode,duals[1:n_subnodes])
@outputs(masternode,solution,scenarios[1:n_subnodes])

@dispatch masternode begin  #creates a set of instructions for which the master node executes when triggered
    if all(hasvalue(duals))
        #@constraint(model,singuct,...) #add the cut
        addCut(model,duals)  #attributes and inputs get their actual values substituted out
        solve(model)
        setoutput(solution,getvalue(model[:w]))  #triggers communication
        setattribute(scenario_data,old_data)
        for i = 1:3
            setoutput(scenarios[i],shift!(scenario_data))
        end
    else
        #send a new scenario to the sub_node that triggered the master
        setoutput(scenarios[scen],shift!(scenario_data))  #only this data gets sent through connection
    end
    set_compute_time(masternode,:wall_time)
end

#add subnodes with instructions
for i 1:3
    sub_node = add_dispatch_node!(workflow)
    #@nodeattributes(sub_node)
    @inputs(sub_node,solution,scenario)
    @outputs(sub_node,dual)
    @dispatch sub_node begin
        m = create_sub_problem(solution,scenario)  #splice in actual values.
        solve(m)
        setoutput(sub_node,getdual(getconstraint(m,:some_constraint)))  #triggers communication
    end
    #Make communication connections
    @connect(workflow, masternode[:solution] => sub_node[:solution])
    @connect(workflow, masternode[:scenarios][i] => sub_node[:scenario])  #2 separate connections between master and subnode
    @connect(workflow,sub_node[:dual] => masternode[:duals][i])

    set_compute_time(sub_node,:wall_time)
end


workflow = Workflow()

master_node = add_dispatch_node!(workflow)
addattributes!(master_node,Dict(:model => create_master()))
#settrigger(master_node,CommunicationReceivedEvent)
set_node_function(master_node,solve_model)
set_node_function_arguments(master_node,[ode_node])            #also see: set_node_function_kwarg
set_result_slot_to_output_channel!(ode_node,1,:x)              #The result will go into output channel :x


#Assume we have 3 processors to do subproblems
sub_node1 = add_dispatch_node!(workflow)
set_node_function(sub_node1,solve_model)
set_node_function_arguments(sub_node1,[ode_node])

sub_node2 = add_dispatch_node!(workflow)
set_node_function(sub_node2,solve_model)
set_node_function_arguments(sub_node2,[ode_node])


sub_node3 = add_dispatch_node!(workflow)
set_node_function(sub_node3,solve_model)
set_node_function_arguments(sub_node3,[ode_node])


trigger!(master_node)

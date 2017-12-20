using JuMP
using Plasmo

m1 = Model()
@variable(m1,x >= 0)
@variable(m1,y >= 0)
@objective(m1,Min,x^2 + y^2)

m2 = Model()
@variable(m2,x >= 2)
@variable(m2,y >= 3)
@objective(m2,Min,x^2 + y^2)

#Physical Graph
graph = PlasmoGraph()  #the physical plasmo graph
n1 = add_node(graph,m1)
n2 = add_node(graph,m2)

#Workflow Graph
work = WorkflowGraph()   #a workflow
w1 = add_node(work,n1)   #a virtual node containing n1
w2 = add_node(work,n2)   #a virtual node containing n2

# add_task(w1,:solve)   #will this actually be a julia task?
# add_task(w2,:solve)   #solve is the most basic task we would use
f1 = (m) -> solve(m)
add_task(w1,f1)

comm1to2 = add_edge(w1,w2)  #communication edge from w1 to w2
comm2to1 = add_edge(w2,w1)

#attributes of a virtual node
w1.graph    #this would just be n1
w1.inputs   #inputs from communication edges
w1.outputs  #outputs to communication edges
w1.tasks    #tasks have states (julia states)

#communicate variables (this might be a very specific instantiation of workflows)
communicate(comm1to2,:x)  #communicate variable x in this channel w1.outputs will map :x to the edge
communicate(comm2to1,:y)  #communicate variable y in this channel

communicate(comm1to2,m1.status)  #communicate the solve status

communicate(comm1to2,n1)  #communicate the entire node

#conditions
condition(w1,:x)  #w1 needs a communication of x to start
condition(w2,:y)  #w2 needs a value for y to start

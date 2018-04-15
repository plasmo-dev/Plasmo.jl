
#Ideas for syntax.  (NOTE Might be able to do this with traits)
# system1 = ModelGraph()
# @addmodel(system1,m1)  #creates a new node
# @variable(m1,x)
# @constraint(m1,x <= 2)
#
# @addmodel(system1,m2)  #creates another new node
# @variable(m2,x)
#
# @linkconstraint(system1,m1[:x] == m2[:x])
#
# system2 = ModelGraph()
# @addmodel(system2,m3)
# @variable(m3,x)
#
# master_system = ModelGraph()
# addsubgraphs(master_system,[system1,system2])
# @linkconstraint(master_system,n1[:y] = )

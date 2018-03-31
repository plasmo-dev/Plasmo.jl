using Plasmo
using PlasmoGraphBase
using JuMP

function simple_model()
    m = Model()
    @variable(m,x)
    @variable(m,y)
    @constraint(m,x + y <= 2)
    @objective(m,Max,x + y)
    return m
end

m = ModelGraph()

n1 = add_node!(m)
n2 = add_node!(m)

setmodel(n1,simple_model())
setmodel(n2,simple_model())

lincon = LinearConstraint(AffExpr([n1[:x],n2[:x]],[1,-1],0),0,0)

edge = addlinkconstraint(m,lincon)  #adds a simple edge between n1 and n2

getlinkconstraints(n1)

ref = getlinkconstraint(m,n2)[1]

linkcon = LinkConstraint(ref)




#should add an edge between n1 and n2
#@linkconstraint(m,n1[:x] == n2[:x])


# #Ideas for syntax.  (NOTE Might be able to do this with traits)
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

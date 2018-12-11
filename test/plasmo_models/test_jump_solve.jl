using Plasmo
using JuMP
using Ipopt

function simple_model()
    m = Model()
    @variable(m,x)
    @variable(m,y)
    @constraint(m,x + y <= 2)
    @objective(m,Max,x + y)
    return m
end

m = ModelGraph()
setsolver(m,IpoptSolver())

n1 = add_node!(m)
n2 = add_node!(m)
n3 = add_node!(m)

setmodel(n1,simple_model())
setmodel(n2,simple_model())
setmodel(n3,simple_model())

lincon1 = LinearConstraint(AffExpr([n1[:x],n2[:x]],[1,-1],0),0,0)
edge1 = addlinkconstraint(m,lincon1)  #adds a simple edge between n1 and n2

#look at link constraints on node 1
getlinkconstraints(n1)

#First link constraint reference on node 2
ref1 = getlinkconstraints(m,n2)[1]

#The actual link constraint
linkcon1 = LinkConstraint(ref1)

lincon2 = LinearConstraint(AffExpr([n1[:x],n2[:x],n3[:x]],[1,-1,1],0),0,0)
edge2 = addlinkconstraint(m,lincon2)  #adds a hyper edge between all 3 nodes
getlinkconstraints(n2)
ref2 = getlinkconstraints(m,n2)[2]
linkcon2 = LinkConstraint(ref2)


@linkconstraint(m,n2[:x] == n3[:x])
solve(m)

return true

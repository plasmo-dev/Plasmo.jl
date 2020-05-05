var documenterSearchIndex = {"docs": [

{
    "location": "#",
    "page": "Introduction",
    "title": "Introduction",
    "category": "page",
    "text": "(Image: Plasmo logo)"
},

{
    "location": "#Plasmo.jl-Platform-for-Scalable-Modeling-and-Optimization-1",
    "page": "Introduction",
    "title": "Plasmo.jl - Platform for Scalable Modeling and Optimization",
    "category": "section",
    "text": "Plasmo.jl is an optimization framework that adopts a modular style to to construct and solve optimization problems. The package provides tools to build and manage complex model structures and offers partitioning capabilities that facilitate using or developing decomposition-based solvers."
},

{
    "location": "#Installation-1",
    "page": "Introduction",
    "title": "Installation",
    "category": "section",
    "text": "Plasmo.jl is a Julia package developed for Julia 1.0. From Julia, Plasmo is installed by using the built-in package manager:import Pkg\nPkg.add(\"Plasmo.jl\")or alternatively from the Julia 1.0 package manager, just do] add PlasmoPlasmo.jl uses JuMP as modeling interface which can be installed withimport Pkg\nPkg.add(\"JuMP\")or using the Julia package manager] add JuMP"
},

{
    "location": "#Example-Script-1",
    "page": "Introduction",
    "title": "Example Script",
    "category": "section",
    "text": "Plasmo.jl uses JuMP to create component models in a ModelGraph, a graph wherein the nodes are component models.  JuMP models are associated with nodes and can have their variables linked to other node variables using LinkConstraints. The below script demonstrates solving a nonlinear optimization problem containing two nodes with a simple link constraint and solving with Ipopt.using JuMP\nusing Plasmo\nusing Ipopt\n\ngraph = ModelGraph()\nsetsolver(graph,IpoptSolver())\n\n#Add nodes to a ModelGraph\nn1 = add_node!(graph)\nn2 = add_node!(graph)\n\n#Create JuMP models\nm1 = Model()\n@variable(m1,0 <= x <= 2)\n@variable(m1,0 <= y <= 3)\n@constraint(m1,x+y <= 4)\n@objective(m1,Min,x)\n\nm2 = Model()\n@variable(m2,x)\n@NLconstraint(m2,exp(x) >= 2)\n\n#Set JuMP models on nodes\nsetmodel(n1,m1)     #set m1 to n1\nsetmodel(n2,m2)\n\n#Link constraints take the same expressions as the JuMP @constraint macro\n@linkconstraint(graph,n1[:x] == n2[:x])\n\n#Get all of the link constraints in a model-graph\nlinks = getlinkconstraints(graph)\n\nsolve(graph)\n\n#Look at individual node solutions\nprintln(\"n1[:x]= \",JuMP.getvalue(n1[:x]))\nprintln(\"n2[:x]= \",JuMP.getvalue(n2[:x]))"
},

{
    "location": "#Contents-1",
    "page": "Introduction",
    "title": "Contents",
    "category": "section",
    "text": "Pages = [\n    \"documentation/modelgraph.md\"\n    \"documentation/graphanalysis.md\"\n    \"documentation/solvers/solvers.md\"\n    ]\nDepth = 2"
},

{
    "location": "#Index-1",
    "page": "Introduction",
    "title": "Index",
    "category": "section",
    "text": ""
},

{
    "location": "documentation/quickstart/#",
    "page": "Quick Start",
    "title": "Quick Start",
    "category": "page",
    "text": ""
},

{
    "location": "documentation/quickstart/#Simple-Plasmo-Example-1",
    "page": "Quick Start",
    "title": "Simple Plasmo Example",
    "category": "section",
    "text": "Plasmo.jl uses modelnodes to construct modular optimization models that have their variables coupled to other modelnodes with linkconstraints. The below script demonstrates solving a nonlinear optimization problem containing two modelnodes with a simple linkconstraint with Ipopt.using Plasmo\nusing Ipopt\n\ngraph = ModelGraph()\n\n#Add nodes to a ModelGraph\n@node(graph,n1)\n@node(graph,n2)\n\n@variable(n1,0 <= x <= 2)\n@variable(n1,0 <= y <= 3)\n@constraint(n1,x+y <= 4)\n@objective(n1,Min,x)\n\n@variable(n2,x)\n@NLnodeconstraint(n2,exp(x) >= 2)\n\n#Add a linkconstraint\n@linkconstraint(graph,n1[:x] == n2[:x])\n\n\nipopt = Ipopt.Optimizer\noptimize!(graph,ipopt)\n\nprintln(\"n1[:x]= \",value(n1,n1[:x]))\nprintln(\"n2[:x]= \",value(n2,n2[:x]))"
},

{
    "location": "documentation/modelgraph/#",
    "page": "Modeling",
    "title": "Modeling",
    "category": "page",
    "text": ""
},

{
    "location": "documentation/modelgraph/#ModelGraph-1",
    "page": "Modeling",
    "title": "ModelGraph",
    "category": "section",
    "text": ""
},

{
    "location": "documentation/modelgraph/#Constructor-1",
    "page": "Modeling",
    "title": "Constructor",
    "category": "section",
    "text": "The ModelGraph is the primary object for creating graph-based models in Plasmo.jl.  A ModelGraph extends the JuMP.AbstractModel and offers a collection of ModelNodes (which also extend JuMP.AbstractModel) which represent solvable optimization problems. ModelNodes are connected by LinkConstraints over variables which induce underlying LinkEdges.  sA ModelGraph does not require any arguments to construct:mg = ModelGraph()A ModelGraph optimizer can be specified in the same way as in JuMP using set_optimizer(::ModelGraph).  An optimizer can be any JuMP compatible solver or a custom Plasmo.jl provided solver (see the solvers section).   For example, we could construct a ModelGraph that uses the IpoptSolver from the Ipopt package:graph = ModelGraph()\nipopt = Ipopt.Optimizer\nset_optimizer(graph,ipopt)"
},

{
    "location": "documentation/modelgraph/#Adding-Nodes-1",
    "page": "Modeling",
    "title": "Adding Nodes",
    "category": "section",
    "text": "ModelNodes can be added to a ModelGraph using the @node macro.  For instance, the below piece of code add the node n1 to the modelgraph mg@node(mg,n1)It is also possible to create sets of ModelNodes in a single call to @node like shown in the below code snippet. This example creates a 2x2 grid of modelnodes.@node(mg,nodes[1:2,1:2])\nfor node in nodes\n    @variable(node,x>=0)\nendWe can iterate over the nodes in a ModelGraph using the getnodes function.  For examplefor node in getnodes(mg)\n    println(node)\nendwill print the string for every node in the ModelGraph graph.  Variables within a ModelNode can be accessed directly from their enclosing node.  @variable(n1,x >= 0)\nprintln(n1[:x])    #accesses variable x on jump_model"
},

{
    "location": "documentation/modelgraph/#Adding-LinkConstraints-1",
    "page": "Modeling",
    "title": "Adding LinkConstraints",
    "category": "section",
    "text": "LinkConstraints are linear constraints that couple variables across different ModelNodes.  The simplest way to add LinkConstraints is to use the @linkconstraint macro.  This macro accepts the same input as a JuMP @constraint macro and creates linear constraints over multiple nodes within the same graph.@variable(nodes[1,1],x >= 0)\n\n@linkconstraint(graph,n1[:x] == nodes[1,1][:x])  #creates a linear constraint between nodes n1 and n2"
},

{
    "location": "documentation/modelgraph/#Subgraph-Structures-1",
    "page": "Modeling",
    "title": "Subgraph Structures",
    "category": "section",
    "text": "It is possible to create subgraphs within a ModelGraph object.  This is helpful when a user wants to develop to separate systems and link them together within a higher level graph.sg1 = ModelGraph()\n@node(sg1,nsubs1[1:2])\nfor node in nsub\n    @variable(node,y[1:2] >= 0 )\nend\n@linkconstraint(sg1,nsubs1[:y][1] == nsubs1[:y][2])  #creates a linear constraint between nodes n1 and n2\n\nsg2 = ModelGraph()\n@node(sg2,nsubs2[1:2])\nfor node in nsub\n    @variable(node,y[1:2] >= 0 )\nend\n@linkconstraint(sg2,nsubs2[:y][1] == nsubs2[:y][2])  #creates a linear constraint between nodes n1 and n2\n\nadd_subgraph!(mg,sg1)\nadd_subgraph!(mg,sg2)\n\n@linkconstraint(mg,nsubs1[:y][2]) == nsubs2[:y][2])"
},

{
    "location": "documentation/modelgraph/#Methods-1",
    "page": "Modeling",
    "title": "Methods",
    "category": "section",
    "text": ""
},

{
    "location": "documentation/modelgraph/#Plasmo.ModelGraph",
    "page": "Modeling",
    "title": "Plasmo.ModelGraph",
    "category": "type",
    "text": "ModelGraph()\n\nThe ModelGraph Type.  Represents a graph containing models (nodes) and the linkconstraints (edges) between them.\n\n\n\n\n\n"
},

{
    "location": "documentation/modelgraph/#ModelGraph-2",
    "page": "Modeling",
    "title": "ModelGraph",
    "category": "section",
    "text": "The ModelGraph contains the following useful methods:Plasmo.ModelGraph"
},

{
    "location": "documentation/modelgraph/#ModelNode-1",
    "page": "Modeling",
    "title": "ModelNode",
    "category": "section",
    "text": "ModelNodes contain methods for managing their contained JuMP models.Plasmo.ModelNode\nPlasmo.@node(graph::ModelGraph)"
},

{
    "location": "documentation/modelgraph/#Attributes-1",
    "page": "Modeling",
    "title": "Attributes",
    "category": "section",
    "text": "Plasmo.getnodes\nPlasmo.all_nodes\nPlasmo.getlinkconstraints\nPlasmo.all_linkconstraints"
},

{
    "location": "documentation/partitioning/#",
    "page": "Partitioning",
    "title": "Partitioning",
    "category": "page",
    "text": ""
},

{
    "location": "documentation/partitioning/#Partitioning-1",
    "page": "Partitioning",
    "title": "Partitioning",
    "category": "section",
    "text": ""
},

{
    "location": "documentation/manipulation/#",
    "page": "Manipulation",
    "title": "Manipulation",
    "category": "page",
    "text": ""
},

{
    "location": "documentation/manipulation/#ModelGraph-Graph-Functions-1",
    "page": "Manipulation",
    "title": "ModelGraph Graph Functions",
    "category": "section",
    "text": "A ModelGraph supports graph analysis functions such as graph partitioning or community detection.  The graph analysis functions are particularly useful for creating decompositions of optimization problems and in fact, this is what is done to use Plasmo\'s built-in structure-based solvers."
},

{
    "location": "documentation/plotting/#",
    "page": "Plotting",
    "title": "Plotting",
    "category": "page",
    "text": ""
},

{
    "location": "documentation/plotting/#Plotting-a-ModelGraph-1",
    "page": "Plotting",
    "title": "Plotting a ModelGraph",
    "category": "section",
    "text": ""
},

{
    "location": "documentation/solvers/#",
    "page": "Solvers",
    "title": "Solvers",
    "category": "page",
    "text": ""
},

{
    "location": "documentation/solvers/#Solvers-1",
    "page": "Solvers",
    "title": "Solvers",
    "category": "section",
    "text": ""
},

{
    "location": "documentation/solvers/#JuMP-Solvers-1",
    "page": "Solvers",
    "title": "JuMP Solvers",
    "category": "section",
    "text": ""
},

{
    "location": "documentation/solvers/#SchwarzSolver-1",
    "page": "Solvers",
    "title": "SchwarzSolver",
    "category": "section",
    "text": ""
},

{
    "location": "documentation/solvers/#PipsSolver-1",
    "page": "Solvers",
    "title": "PipsSolver",
    "category": "section",
    "text": "The PipsSolver solves nonlinear optimization problems with PIPS-NLP."
},

{
    "location": "tutorials/tutorials/#",
    "page": "Tutorials",
    "title": "Tutorials",
    "category": "page",
    "text": ""
},

{
    "location": "tutorials/tutorials/#Tutorials-1",
    "page": "Tutorials",
    "title": "Tutorials",
    "category": "section",
    "text": ""
},

{
    "location": "tutorials/tutorials/#MicroGrid-Modeling-1",
    "page": "Tutorials",
    "title": "MicroGrid Modeling",
    "category": "section",
    "text": ""
},

]}

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
    "text": "Plasmo.jl is a modeling and optimization interface for constructing and solving optimization problems that exploits a graph-aware structure. The package provides modular model building for optimization problems and graph analysis capabilities that the enable the use of decomposition-based solvers."
},

{
    "location": "#Installation-1",
    "page": "Introduction",
    "title": "Installation",
    "category": "section",
    "text": "Plasmo.jl is a Julia package developed for Julia 1.0. From Julia, Plasmo is installed by using the built-in package manager:import Pkg\nPkg.clone(\"https://github.com/jalving/Plasmo.jl\")or alternatively from the Julia 1.0 package manager, just do] add https://github.com/jalving/Plasmo.jlPlasmo.jl uses JuMP as modeling interface which can be installed withimport Pkg\nPkg.add(\"JuMP\")or using the Julia package manager] add JuMP"
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
    "location": "quick_start/quickstart/#",
    "page": "Quick Start",
    "title": "Quick Start",
    "category": "page",
    "text": ""
},

{
    "location": "quick_start/quickstart/#Simple-Plasmo-Example-1",
    "page": "Quick Start",
    "title": "Simple Plasmo Example",
    "category": "section",
    "text": "Plasmo.jl uses JuMP to create component models in a ModelGraph.  JuMP models are associated with nodes and can have their variables connected to other nodes (models) with linkconstraints. The below script demonstrates solving a nonlinear optimization problem containing two nodes with a simple link constraint between them and solving with Ipopt.using JuMP\nusing Plasmo\nusing Ipopt\n\ngraph = ModelGraph()\nsetsolver(graph,IpoptSolver())\n\n#Add nodes to a ModelGraph\nn1 = add_node!(graph)\nn2 = add_node!(graph)\n\n#Create JuMP models\nm1 = Model()\n@variable(m1,0 <= x <= 2)\n@variable(m1,0 <= y <= 3)\n@constraint(m1,x+y <= 4)\n@objective(m1,Min,x)\n\nm2 = Model()\n@variable(m2,x)\n@NLconstraint(m2,exp(x) >= 2)\n\n#Set JuMP models on nodes\nsetmodel(n1,m1)     #set m1 to node 1.  Updates reference on m1\nsetmodel(n2,m2)\n\n#Link constraints take the same expressions as the JuMP @constraint macro\n@linkconstraint(graph,n1[:x] == n2[:x])\n\n#Get all of the link constraints in a graph\nlinks = getlinkconstraints(graph)\n\nsolve(graph)\n\nprintln(\"n1[:x]= \",JuMP.getvalue(n1[:x]))\nprintln(\"n2[:x]= \",JuMP.getvalue(n2[:x]))"
},

{
    "location": "documentation/modelgraph/#",
    "page": "ModelGraph",
    "title": "ModelGraph",
    "category": "page",
    "text": ""
},

{
    "location": "documentation/modelgraph/#ModelGraph-1",
    "page": "ModelGraph",
    "title": "ModelGraph",
    "category": "section",
    "text": ""
},

{
    "location": "documentation/modelgraph/#Constructor-1",
    "page": "ModelGraph",
    "title": "Constructor",
    "category": "section",
    "text": "The ModelGraph is the primary object for creating graph-based models in Plasmo.jl.  A ModelGraph is a collection of ModelNodes which are connected by LinkConstraints (i.e. edges) over variables.  One way to think of the structure of a ModelGraph is a HyperGraph wherein edges represent linking constraints that can link multiple ModelNode variables.A ModelGraph does not require any arguments to construct:mg = ModelGraph()A ModelGraph solver can be specified upon construction using the solver keyword argument.  A solver can be any JuMP compatible solver or a Plasmo.jl provided solver (see solvers section).   For example, we could construct a ModelGraph that uses the IpoptSolver from the Ipopt package:graph = ModelGraph(solver = IpoptSolver())"
},

{
    "location": "documentation/modelgraph/#Adding-Nodes-1",
    "page": "ModelGraph",
    "title": "Adding Nodes",
    "category": "section",
    "text": "Nodes can be added to a ModelGraph using the add_node! function.  By default, a node contains an empty JuMP Model object.n1 = add_node!(graph)A model can be set upon creation by providing a second argument.  For example:model = JuMP.Model()\nn1 = add_node!(graph,model)  #sets model to n1where model is a JuMP Model object.  We can also set a model on a node after construction:setmodel(n1,model)This can be helpful in instances where a user wants to swap out a model on a node without changing the graph topology.  Keep in mind however that swapping out a model will by default remove any link-constraints that involve that node.  Also note that any single JuMP Model can only be assigned to a single node.We can also iterate over the nodes in a ModelGraph using the getnodes function.  For examplefor node in getnodes(graph)\n    println(node)\nendwill print the string for every node in the ModelGraph graph.  ModelNodes can also be retrieved based on their index within a ModelGraph or vic versa.   For example, since n1 was the first node added to mg, it will have an index of 1.n1 == getnode(mg,1)   #will return true\ngetindex(graph,n1) == 1  #will also return trueVariables within a JuMP Model can be accessed directly from their enclosing node.  jump_model = Model()\n@variable(jump_model,x >= 0)\nsetmodel(n1,jump_model)\nprintln(n1[:x])    #accesses variable x on jump_model"
},

{
    "location": "documentation/modelgraph/#Adding-LinkConstraints-1",
    "page": "ModelGraph",
    "title": "Adding LinkConstraints",
    "category": "section",
    "text": "LinkConstraints are linear constraints that couple variables across different ModelNodes.  The simplest way to add LinkConstraints is to use the @linkconstraint macro.  This macro accepts the same input as a JuMP @constraint macro and creates linear constraints over multiple nodes within the same graph.jump_2 = Model()\n@variable(jump_2,x >= 0)\nn2 = add_node!(graph,jump_2)\n\n@linkconstraint(graph,n1[:x] == n2[:x])  #creates a linear constraint between nodes n1 and n2"
},

{
    "location": "documentation/modelgraph/#Subgraph-Structures-1",
    "page": "ModelGraph",
    "title": "Subgraph Structures",
    "category": "section",
    "text": "It is possible to create subgraphs within a ModelGraph object.  This is helpful when a user wants to develop to separate systems and link them together within a higher level graph.(Section TBD)"
},

{
    "location": "documentation/modelgraph/#Methods-1",
    "page": "ModelGraph",
    "title": "Methods",
    "category": "section",
    "text": ""
},

{
    "location": "documentation/modelgraph/#Plasmo.PlasmoModelGraph.ModelGraph",
    "page": "ModelGraph",
    "title": "Plasmo.PlasmoModelGraph.ModelGraph",
    "category": "type",
    "text": "ModelGraph()\n\nThe ModelGraph Type.  Represents a graph containing models (nodes) and the linkconstraints (edges) between them. A ModelGraph wraps a BasePlasmoGraph and can use its methods.  A ModelGraph also wraps a LinkModel object which extends a JuMP AbstractModel to provide model management functions.\n\n\n\n\n\n"
},

{
    "location": "documentation/modelgraph/#JuMP.getobjectivevalue",
    "page": "ModelGraph",
    "title": "JuMP.getobjectivevalue",
    "category": "function",
    "text": "Get the ModelGraph objective value\n\n\n\n\n\nGet node objective value\n\n\n\n\n\n"
},

{
    "location": "documentation/modelgraph/#Plasmo.PlasmoModelGraph.getinternaljumpmodel",
    "page": "ModelGraph",
    "title": "Plasmo.PlasmoModelGraph.getinternaljumpmodel",
    "category": "function",
    "text": "Get the current created JuMP model for the ModelGraph.  Only created when solving using a JuMP compliant solver.\n\n\n\n\n\n"
},

{
    "location": "documentation/modelgraph/#JuMP.setsolver-Tuple{AbstractModelGraph,MathProgBase.SolverInterface.AbstractMathProgSolver}",
    "page": "ModelGraph",
    "title": "JuMP.setsolver",
    "category": "method",
    "text": "setsolver(model::AbstractModelGraph,solver::AbstractMathProgSolver)\n\nSet the graph solver to use an AbstractMathProg compliant solver\n\n\n\n\n\n"
},

{
    "location": "documentation/modelgraph/#JuMP.setsolver-Tuple{AbstractModelGraph,AbstractPlasmoSolver}",
    "page": "ModelGraph",
    "title": "JuMP.setsolver",
    "category": "method",
    "text": "setsolver(model::AbstractModelGraph,solver::AbstractPlasmoSolver)\n\nSet the graph solver to use an AbstractMathProg compliant solver\n\n\n\n\n\n"
},

{
    "location": "documentation/modelgraph/#Plasmo.PlasmoModelGraph.getsolver",
    "page": "ModelGraph",
    "title": "Plasmo.PlasmoModelGraph.getsolver",
    "category": "function",
    "text": "Get the ModelGraph solver\n\n\n\n\n\n"
},

{
    "location": "documentation/modelgraph/#ModelGraph-2",
    "page": "ModelGraph",
    "title": "ModelGraph",
    "category": "section",
    "text": "The ModelGraph contains the following useful methods:Plasmo.PlasmoModelGraph.ModelGraph\nPlasmo.PlasmoModelGraph.getobjectivevalue\nPlasmo.PlasmoModelGraph.getinternaljumpmodel\nsetsolver(model::AbstractModelGraph,solver::MathProgBase.AbstractMathProgSolver)\nsetsolver(model::AbstractModelGraph,solver::AbstractPlasmoSolver)\nPlasmo.PlasmoModelGraph.getsolver"
},

{
    "location": "documentation/modelgraph/#Plasmo.PlasmoModelGraph.ModelNode",
    "page": "ModelGraph",
    "title": "Plasmo.PlasmoModelGraph.ModelNode",
    "category": "type",
    "text": "The ModelNode type\n\nModelNode()\n\nCreates an empty ModelNode.  Does not add it to a graph.\n\n\n\n\n\n"
},

{
    "location": "documentation/modelgraph/#Plasmo.PlasmoGraphBase.add_node!-Tuple{AbstractModelGraph,JuMP.AbstractModel}",
    "page": "ModelGraph",
    "title": "Plasmo.PlasmoGraphBase.add_node!",
    "category": "method",
    "text": "add_node!(graph::AbstractModelGraph)\n\nAdd a ModelNode to a ModelGraph.\n\n\n\n\n\n"
},

{
    "location": "documentation/modelgraph/#Plasmo.PlasmoModelGraph.setmodel-Tuple{ModelNode,JuMP.AbstractModel}",
    "page": "ModelGraph",
    "title": "Plasmo.PlasmoModelGraph.setmodel",
    "category": "method",
    "text": "setmodel(node::ModelNode,m::AbstractModel)\n\nSet the model on a node.  This will delete any link-constraints the node is currently part of\n\n\n\n\n\n"
},

{
    "location": "documentation/modelgraph/#Plasmo.PlasmoModelGraph.is_nodevar",
    "page": "ModelGraph",
    "title": "Plasmo.PlasmoModelGraph.is_nodevar",
    "category": "function",
    "text": "is_nodevar(node::ModelNode,var::AbstractJuMPScalar)\n\nCheck whether a JuMP variable belongs to a ModelNode\n\n\n\n\n\n"
},

{
    "location": "documentation/modelgraph/#Plasmo.PlasmoGraphBase.getnode-Tuple{JuMP.AbstractModel}",
    "page": "ModelGraph",
    "title": "Plasmo.PlasmoGraphBase.getnode",
    "category": "method",
    "text": "getnode(model::AbstractModel)\n\nGet the ModelNode corresponding to a JuMP Model\n\n\n\n\n\n"
},

{
    "location": "documentation/modelgraph/#Plasmo.PlasmoGraphBase.getnode-Tuple{JuMP.AbstractJuMPScalar}",
    "page": "ModelGraph",
    "title": "Plasmo.PlasmoGraphBase.getnode",
    "category": "method",
    "text": "getnode(model::AbstractModel)\n\nGet the ModelNode corresponding to a JuMP Variable\n\n\n\n\n\n"
},

{
    "location": "documentation/modelgraph/#ModelNode-1",
    "page": "ModelGraph",
    "title": "ModelNode",
    "category": "section",
    "text": "ModelNodes contain methods for managing their contained JuMP models.Plasmo.PlasmoModelGraph.ModelNode\nPlasmo.PlasmoModelGraph.add_node!(graph::AbstractModelGraph,model::JuMP.AbstractModel)\nPlasmo.PlasmoModelGraph.setmodel(node::ModelNode,model::JuMP.AbstractModel)\nPlasmo.PlasmoModelGraph.is_nodevar\nPlasmo.PlasmoModelGraph.getnode(model::JuMP.AbstractModel)\nPlasmo.PlasmoModelGraph.getnode(var::JuMP.AbstractJuMPScalar)"
},

{
    "location": "documentation/modelgraph/#Plasmo.PlasmoModelGraph.getlinkconstraints-Tuple{AbstractModelGraph}",
    "page": "ModelGraph",
    "title": "Plasmo.PlasmoModelGraph.getlinkconstraints",
    "category": "method",
    "text": "getlinkconstraints(graph::AbstractModelGraph)\n\nReturn Array of all LinkConstraints in the ModelGraph graph\n\n\n\n\n\n"
},

{
    "location": "documentation/modelgraph/#Plasmo.PlasmoModelGraph.getsimplelinkconstraints",
    "page": "ModelGraph",
    "title": "Plasmo.PlasmoModelGraph.getsimplelinkconstraints",
    "category": "function",
    "text": "getsimplelinkconstraints(model::AbstractModelGraph)\n\nRetrieve link-constraints that only connect two nodes\"\n\n\n\n\n\n"
},

{
    "location": "documentation/modelgraph/#Plasmo.PlasmoModelGraph.gethyperlinkconstraints",
    "page": "ModelGraph",
    "title": "Plasmo.PlasmoModelGraph.gethyperlinkconstraints",
    "category": "function",
    "text": "gethyperlinkconstraints(model::AbstractModelGraph)\n\nRetrieve link-constraints that connect three or more nodes\"\n\n\n\n\n\n"
},

{
    "location": "documentation/modelgraph/#Plasmo.PlasmoModelGraph.get_all_linkconstraints",
    "page": "ModelGraph",
    "title": "Plasmo.PlasmoModelGraph.get_all_linkconstraints",
    "category": "function",
    "text": "getalllinkconstraints(graph::AbstractModelGraph)\n\nGet a list containing every link constraint in the graph, including its subgraphs\n\n\n\n\n\n"
},

{
    "location": "documentation/modelgraph/#Plasmo.PlasmoModelGraph.addlinkconstraint",
    "page": "ModelGraph",
    "title": "Plasmo.PlasmoModelGraph.addlinkconstraint",
    "category": "function",
    "text": "Add a single link-constraint to the ModelGraph\n\n\n\n\n\nAdd a vector of link-constraints to the ModelGraph\n\n\n\n\n\n"
},

{
    "location": "documentation/modelgraph/#Plasmo.PlasmoModelGraph.getlinkconstraints-Tuple{AbstractModelGraph,ModelNode}",
    "page": "ModelGraph",
    "title": "Plasmo.PlasmoModelGraph.getlinkconstraints",
    "category": "method",
    "text": "getlinkconstraints(graph::AbstractModelGraph,node::ModelNode)\n\nReturn Array of LinkConstraints for the node\n\n\n\n\n\n"
},

{
    "location": "documentation/modelgraph/#Plasmo.PlasmoModelGraph.getlinkconstraints-Tuple{ModelNode}",
    "page": "ModelGraph",
    "title": "Plasmo.PlasmoModelGraph.getlinkconstraints",
    "category": "method",
    "text": "getlinkconstraints(node::ModelNode)\n\nReturn a Dictionary of LinkConstraints for each graph the node is a member of\n\n\n\n\n\n"
},

{
    "location": "documentation/modelgraph/#LinkConstraints-1",
    "page": "ModelGraph",
    "title": "LinkConstraints",
    "category": "section",
    "text": "Plasmo.PlasmoModelGraph.getlinkconstraints(graph::AbstractModelGraph)\nPlasmo.PlasmoModelGraph.getsimplelinkconstraints\nPlasmo.PlasmoModelGraph.gethyperlinkconstraints\nPlasmo.PlasmoModelGraph.get_all_linkconstraints\nPlasmo.PlasmoModelGraph.addlinkconstraint\nPlasmo.PlasmoModelGraph.getlinkconstraints(graph::AbstractModelGraph,node::ModelNode)\nPlasmo.PlasmoModelGraph.getlinkconstraints(node::ModelNode)\n"
},

{
    "location": "documentation/graphanalysis/#",
    "page": "Graph Analysis",
    "title": "Graph Analysis",
    "category": "page",
    "text": ""
},

{
    "location": "documentation/graphanalysis/#ModelGraph-Analysis-1",
    "page": "Graph Analysis",
    "title": "ModelGraph Analysis",
    "category": "section",
    "text": "A ModelGraph supports graph analysis functions such as graph partitioning or community detection.  The graph analysis functions are particularly useful for creating decompositions of optimization problems and in fact, this is what is done to use Plasmo\'s built-in structure-based solvers."
},

{
    "location": "documentation/graphanalysis/#Partitioning-1",
    "page": "Graph Analysis",
    "title": "Partitioning",
    "category": "section",
    "text": "Graph partitioning can be performed on a ModelGraph using Metis.partition.  The function requires a working Metis interface, which can be cloned with:using Pkg\nPkg.clone(\"https://github.com/jalving/Metis.jl.git\")Once Metis is installed, graph partitions can be obtained like following:using Metis\n#Assuming we have a ModelGraph\npartitions = Metis.partition(graph,4,alg = :KWAY)  #Use the Metis KWAY partitionwhere partitions will be a vector of vectors.  Each vector will contain the indices of the nodes in graph.  Partitions can be used to communicate structure to PlasmoSolvers or the PipsSolver if PlasmoSolverInterface is installed."
},

{
    "location": "documentation/graphanalysis/#Metis.partition-Tuple{ModelGraph,Int64}",
    "page": "Graph Analysis",
    "title": "Metis.partition",
    "category": "method",
    "text": "partition(graph::ModelGraph,n_parts::Int64;alg = :KWAY) –> Vector{Vector{Int64}}\n\nReturn a graph partition containing a vector of a vectors of node indices.\n\n\n\n\n\n"
},

{
    "location": "documentation/graphanalysis/#LightGraphs.label_propagation-Tuple{ModelGraph}",
    "page": "Graph Analysis",
    "title": "LightGraphs.label_propagation",
    "category": "method",
    "text": "LightGraphs.label_propagation(graph::ModelGraph)\n\nReturn partitions corresponding to detected communities using the LightGraphs label propagation algorithm.\n\n\n\n\n\n"
},

{
    "location": "documentation/graphanalysis/#Methods-1",
    "page": "Graph Analysis",
    "title": "Methods",
    "category": "section",
    "text": "Metis.partition(graph::ModelGraph,n_parts::Int64)\nLightGraphs.label_propagation(graph::ModelGraph)"
},

{
    "location": "documentation/solvers/solvers/#",
    "page": "Solvers",
    "title": "Solvers",
    "category": "page",
    "text": ""
},

{
    "location": "documentation/solvers/solvers/#Solvers-1",
    "page": "Solvers",
    "title": "Solvers",
    "category": "section",
    "text": ""
},

{
    "location": "documentation/solvers/solvers/#JuMP-Solvers-1",
    "page": "Solvers",
    "title": "JuMP Solvers",
    "category": "section",
    "text": "Any MathProgBase compliant JuMP solver can be used to solve a ModelGraph object.  In this case, the entire ModelGraph will be aggregated into a JuMP model and will use the JuMP solve function.  The solution updates the ModelGraph nodes and Linkconstraints with corresponding variable and dual values."
},

{
    "location": "documentation/solvers/solvers/#Plasmo-Solvers-1",
    "page": "Solvers",
    "title": "Plasmo Solvers",
    "category": "section",
    "text": "Built-in Plasmo solvers include a BendersSolver and LagrangeSolver"
},

{
    "location": "documentation/solvers/solvers/#LagrangeSolver-1",
    "page": "Solvers",
    "title": "LagrangeSolver",
    "category": "section",
    "text": "The LagrangeSolver will perform a Lagrangean decomposition algorithm which will dualize all linking constraints for any arbitrary graph. It could be a tree, it could be a sequence of nodes connected (e.g. temporal decomposition), or it may even contain cycles."
},

{
    "location": "documentation/solvers/solvers/#Useage-1",
    "page": "Solvers",
    "title": "Useage",
    "category": "section",
    "text": "lagrangesolve(graph::ModelGraph;update_method,ϵ,timelimit,lagrangeheuristic,initialmultipliers,α,δ,maxnoimprove,cpbound), solves the graph using the lagrangean decomposition algorithmA solver can also be created using LagrangeSolver([options])"
},

{
    "location": "documentation/solvers/solvers/#Options-1",
    "page": "Solvers",
    "title": "Options",
    "category": "section",
    "text": "update_method Multiplier update method\nallowed values: :subgradient, :probingsubgradient, :marchingstep, :intersectionstep, :cuttingplanes\ndefault: :subgradient\nϵ Convergence tolerance\ndefault: 0.001\ntimelimit Algorithm time limit in seconds\ndefault: 3600 (1 hour)\nlagrangeheuristic Function to solve the lagrangean heuristic. PlasmoAlgorithms provides 2 heuristic functions: fixbinaries, fixintegers\ndefault: fixbinaries\ninitialmultipliers initialization method for lagrangean multipliers. When :relaxation is selected the algorithm will use the multipliers from the LP relaxation\nallowed values: :zero,:relaxation\ndefault: zero\nα Initial value for the step parameter in subgradient methods\ndefault: 2\nδ Shrinking factor for α\ndefault: 0.5\nmaxnoimprove Number of iterations without improvement before shrinking α\ndefault: 3"
},

{
    "location": "documentation/solvers/solvers/#Multiplier-updated-methods-1",
    "page": "Solvers",
    "title": "Multiplier updated methods",
    "category": "section",
    "text": "It supports the following methods for updating the lagrangean multipliers:Subgradient\nProbing Subgradient\nMarching Step\nIntersection Step (experimental)\nInteractive\nCutting Planes\nCutting planes with trust region\nLevels"
},

{
    "location": "documentation/solvers/solvers/#BendersSolver-1",
    "page": "Solvers",
    "title": "BendersSolver",
    "category": "section",
    "text": ""
},

{
    "location": "documentation/solvers/solvers/#External-Solvers-1",
    "page": "Solvers",
    "title": "External Solvers",
    "category": "section",
    "text": ""
},

{
    "location": "documentation/solvers/solvers/#PipsSolver-1",
    "page": "Solvers",
    "title": "PipsSolver",
    "category": "section",
    "text": "The PipsSolver solves nonlinear optimization problems with PIPS-NLP using a defined structure (similar to StructJuMP)."
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
    "location": "tutorials/tutorials/#Convert-ModelGraph-to-JuMP-Model-1",
    "page": "Tutorials",
    "title": "Convert ModelGraph to JuMP Model",
    "category": "section",
    "text": "using JuMP\nusing Plasmo\nusing Ipopt\n\ngraph = ModelGraph()\nsetsolver(graph,Ipopt.IpoptSolver())\n\n#Add nodes to a GraphModel\nn1 = add_node(graph)\nn2 = add_node(graph)\n\nm1 = JuMP.Model()\n@variable(m1,0 <= x <= 2)\n@variable(m1,0 <= y <= 3)\n@constraint(m1,x+y <= 4)\n@objective(m1,Min,x)\n\nm2 = Model()\n@variable(m2,x)\n@NLconstraint(m2,exp(x) >= 2)\n\n\n#Set models on nodes and edges\nsetmodel(n1,m1)     #set m1 to node 1.  Updates reference on m1\nsetmodel(n2,m2)\n\n#Link constraints take the same expressions as the JuMP @constraint macro\n@linkconstraint(graph,n1[:x] == n2[:x])\n\n#Get all of the link constraints in a graph\nlinks = getlinkconstraints(graph)\nfor link in links\n    println(link)\nend\n\njump_model = create_jump_graph_model(graph)\njump_model.solver = IpoptSolver()\n\nsolve(jump_model)\n\nlinks = getlinkconstraints(jump_model)\n\ngetdual(links[1])"
},

{
    "location": "tutorials/tutorials/#Using-the-LagrangeSolver-1",
    "page": "Tutorials",
    "title": "Using the LagrangeSolver",
    "category": "section",
    "text": "using JuMP\nusing GLPKMathProgInterface\nusing Plasmo\n\nm1 = Model(solver=GLPKSolverMIP())\n\n@variable(m1, xm[i in 1:2],Bin)\n@constraint(m1, xm[1] + xm[2] <= 1)\n@objective(m1, Max, 16xm[1] + 10xm[2])\n\n## Model on y`\n# Max  4y[2]\n# s.t. y[1] + y[2] <= 1\n#      8x[1] + 2x[2] + y[1] + 4y[2] <= 10\n#      x, y ∈ {0,1}\n\n#m2 = Model(solver=GurobiSolver(OutputFlag=0))\nm2 = Model(solver=GLPKSolverMIP())\n@variable(m2, xs[i in 1:2],Bin)\n@variable(m2, y[i in 1:2], Bin)\n@constraint(m2, y[1] + y[2] <= 1)\n@constraint(m2, 8xs[1] + 2xs[2] + y[1] + 4y[2] <= 10)\n@objective(m2, Max, 4y[2])\n\n## Model Graph\ngraph = ModelGraph()\nheur(g) = 16\nsetsolver(graph, LagrangeSolver(update_method=:subgradient,max_iterations=30,lagrangeheuristic=heur))\nn1 = add_node(graph)\nsetmodel(n1,m1)\nn2 = add_node(graph)\nsetmodel(n2,m2)\n\n## Linking\n# m1[x] = m2[x]  ∀i ∈ {1,2}\n@linkconstraint(graph, [i in 1:2], n1[:xm][i] == n2[:xs][i])\n\nsolution = solve(graph)"
},

{
    "location": "low_level/baseplasmograph/#",
    "page": "Low-Level Functions",
    "title": "Low-Level Functions",
    "category": "page",
    "text": ""
},

{
    "location": "low_level/baseplasmograph/#BasePlasmoGraph-1",
    "page": "Low-Level Functions",
    "title": "BasePlasmoGraph",
    "category": "section",
    "text": "A BasePlasmoGraph wraps a LightGraphs.jl AbstractGraph and adds additional attributes for managing subgraphs and data. These are all of the graph functions a user might use in Plasmo.  Most core functions from LightGraphs.jl have been extended for a PlasmoGraph."
},

{
    "location": "low_level/baseplasmograph/#Plasmo.PlasmoGraphBase.BasePlasmoGraph",
    "page": "Low-Level Functions",
    "title": "Plasmo.PlasmoGraphBase.BasePlasmoGraph",
    "category": "type",
    "text": "BasePlasmoGraph()\n\nThe BasePlasmoGraph Type.  The BasePlasmoGraph wraps a LightGraphs.AbstractGraph (such as a LightGraphs.Graph or LightGraphs.DiGraph). The BasePlasmoGraph extends a LightGraphs.AbstractGraph and adds a label (i.e. a name), an index, attributes (a dictionary), and a nodedict and edgedict to map nodes and edges to indices. Most notable is the addition of a subgraphlist.  A BasePlasmoGraph contains a list of other AbstractPlasmoGraph objects reprsenting subgraphs within the BasePlasmoGraph.  The index therefore, is the PlasmoGraph index within its parent graph.  An index of 0 means the graph is the top-level graph (i.e. it is not a subgraph of any other graph).\n\n\n\n\n\n"
},

{
    "location": "low_level/baseplasmograph/#Base.getindex-Tuple{BasePlasmoGraph}",
    "page": "Low-Level Functions",
    "title": "Base.getindex",
    "category": "method",
    "text": "getindex(basegraph::BasePlasmoGraph)\n\nGet a basegraph index\n\n\n\n\n\n"
},

{
    "location": "low_level/baseplasmograph/#Base.getindex-Tuple{BasePlasmoGraph,BasePlasmoNode}",
    "page": "Low-Level Functions",
    "title": "Base.getindex",
    "category": "method",
    "text": "getindex(basegraph::BasePlasmoGraph,basenode::BasePlasmoNode)\n\nGet the index of the node in the BasePlasmoGraph\n\n\n\n\n\n"
},

{
    "location": "low_level/baseplasmograph/#Graph-Functions-1",
    "page": "Low-Level Functions",
    "title": "Graph Functions",
    "category": "section",
    "text": "BasePlasmoGraph\ngetindex(::BasePlasmoGraph)\ngetindex(::BasePlasmoGraph,::BasePlasmoNode)"
},

]}

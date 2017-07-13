import JuMP: isexpr, constraint_error, quot, getname, buildrefsets,_canonicalize_sense,parseExprToplevel, AffExpr, getloopedcode,addtoexpr_reorder,
constructconstraint!,ConstraintRef,AbstractConstraint,@constraint,JuMPArray

#macro for defining linkconstraints between nodes and edges.  Link constraints are associated with nodes and edges within their respective graph.
macro linkconstraint(graph,args...)
    #Check the inputs are the correct types.  This needs to throw
    checkinputs = quote
        #@assert Plasmo.is_graphmodel($m)
        @assert isa($graph,Plasmo.PlasmoGraph)
        #@assert isa($nodeoredge,Plasmo.NodeOrEdge)
    end
    #generate constraint list and them to node or edge linkdata
    refscode = quote
        cons_refs = Plasmo.@getconstraintlist($(args...))           #returns all of the constraints that would be generated from the expression
        # println(cons_refs)
        # println(cons_refs.innerArray)
        if isa(cons_refs,JuMP.JuMPArray)
            cons_refs = cons_refs.innerArray
        end
        Plasmo._addlinkconstraint!($graph,cons_refs)    #add the link constraints to the node or edge and map to graph
    end
    return esc(quote
        begin
            $checkinputs
            $refscode
        end
    end)
end

macro NLlinkconstraint(graph,args...) end

#generate a list of constraints, but don't attach them to the model @Might be the same as JuMP.LinearConstraints
macro getconstraintlist(args...)
        # Pick out keyword arguments
        if isexpr(args[1],:parameters) # these come if using a semicolon
            kwargs = args[1]
            args = args[2:end]
        else
            kwargs = Expr(:parameters)
        end

        kwsymbol = VERSION < v"0.6.0-dev.1934" ? :kw : :(=) #changed by julia PR #19868
        append!(kwargs.args, filter(x -> isexpr(x, kwsymbol), collect(args)))# comma separated
        args = filter(x->!isexpr(x, kwsymbol), collect(args))

        if length(args) < 1
            if length(kwargs.args) > 0
                constraint_error(args, "Not enough positional arguments")
            else
                constraint_error(args, "Not enough arguments")
            end
        end
        x = args[1]
        extra = args[2:end]

        # Two formats:
        #@constraint(m, a*x <= 5)
        #@constraint(m, myref[a=1:5], a*x <= 5)
        length(extra) > 1 && constraint_error(args, "Too many arguments.")
        # Canonicalize the arguments
        c = length(extra) == 1 ? x        : gensym()  #this is either the index set or a generated variable
        x = length(extra) == 1 ? extra[1] : x         #this is always the constraint expression
        anonvar = isexpr(c, :vect) || isexpr(c, :vcat) || length(extra) != 1
        variable = gensym()
        quotvarname = quot(getname(c))
        escvarname = anonvar ? variable : esc(getname(c))
        if isa(x, Symbol)
            constraint_error(args, "Incomplete constraint specification $x. Are you missing a comparison (<=, >=, or ==)?")
        end
        (x.head == :block) &&
          constraint_error(args, "Code block passed as constraint. Perhaps you meant to use @constraints instead?")
         refcall, idxvars, idxsets, idxpairs, condition = buildrefsets(c, variable)
        if isexpr(x, :call)
            if x.args[1] == :in
                @assert length(x.args) == 3
                newaff, parsecode = parseExprToplevel(x.args[2], :q)
                constraintcall = :(addconstraint($m, constructconstraint!($newaff,$(esc(x.args[3])))))
            else
                # Simple comparison - move everything to the LHS
                @assert length(x.args) == 3
                (sense,vectorized) = _canonicalize_sense(x.args[1])
                lhs = :($(x.args[2]) - $(x.args[3]))
                #addconstr = (vectorized ? :addVectorizedConstraint : :addconstraint)
                newaff, parsecode = parseExprToplevel(lhs, :q)
                constraintcall = :(constructconstraint!($newaff,$(quot(sense))))
            end
            code = quote
                q = zero(AffExpr)
                $parsecode
                $(refcall) = $constraintcall
        end
        loopedcode = getloopedcode(variable, code, condition, idxvars, idxsets, idxpairs, :AbstractConstraint)  #trying abstract constraint
    end
    return quote
      $loopedcode
      $escvarname
    end
end

import JuMP: isexpr, constraint_error, quot, getname, buildrefsets,_canonicalize_sense,parseExprToplevel, AffExpr, getloopedcode,addtoexpr_reorder,
constructconstraint!,ConstraintRef,AbstractConstraint,JuMPArray,JuMPDict,addkwargs!,coeftype,undef,
macro_return,macro_assign_and_return

#Would need to create link variables to do this
macro NLlinkconstraint(graph,args...) end

#TODO
#Graph objective should be a sum of node objectives
#Should work similar to JuMPs @objective
macro graphobjective(graph,args...)
    graph = esc(graph)
    if length(args) != 2
        # Either just an objective sense, or just an expression.
        error("in @graphobjective: needs three arguments: graph, objective sense (Max or Min) and expression.")
    end
    sense, x = args
    if sense == :Min || sense == :Max
        sense = Expr(:quote,sense)
    end
    newaff, parsecode = parseExprToplevel(x, :q)
    code = quote
        q = zero(AffExpr)
        $parsecode
        setobjective($graph, $(esc(sense)), $newaff)
    end
    return assert_validmodel(m, code)
end


#generate a list of constraints, but don't attach them to the model @Might be the same as JuMP.LinearConstraints
macro getconstraintlist(args...)
        # Pick out keyword arguments
        if isexpr(args[1],:parameters) # these come if using a semicolon
            kwargs = args[1]
            args = args[2:end]
        else
            kwargs = Expr(:parameters)
        end

        #kwsymbol = VERSION < v"0.6.0-dev.1934" ? :kw : :(=) #changed by julia PR #19868
        kwsymbol = :(=) # changed by julia PR #19868
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
        # x = args[2]
        # extra = args[3:end]


        # Two formats:
        #@constraint(m, a*x <= 5)
        #@constraint(m, myref[a=1:5], a*x <= 5)
        length(extra) > 1 && constraint_error(args, "Too many arguments.")
        # Canonicalize the arguments
        c = length(extra) == 1 ? x        : gensym()  #this is either the index set or a generated variable
        x = length(extra) == 1 ? extra[1] : x         #this is always the constraint expression

        anonvar = isexpr(c, :vect) || isexpr(c, :vcat) || length(extra) != 1
        variable = gensym()

        # quotvarname = quot(getname(c))
        # escvarname = anonvar ? variable : esc(getname(c))

        if isa(x, Symbol)
            constraint_error(args, "Incomplete constraint specification $x. Are you missing a comparison (<=, >=, or ==)?")
        end

        (x.head == :block) && constraint_error(args, "Code block passed as constraint. Perhaps you meant to use @constraints instead?")

        refcall, idxvars, idxsets, idxpairs, condition = buildrefsets(c, variable)

        if isexpr(x, :call)

            if x.args[1] == :in
                @assert length(x.args) == 3
                newaff, parsecode = parseExprToplevel(x.args[2], :q)
                #constraintcall = :(addconstraint($m, constructconstraint!($newaff,$(esc(x.args[3])))))
                constraintcall = :(constructconstraint!($newaff,$(esc(x.args[3]))))
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
        elseif isexpr(x, :comparison)
            # Ranged row
            (lsign,lvectorized) = _canonicalize_sense(x.args[2])
            (rsign,rvectorized) = _canonicalize_sense(x.args[4])
            if (lsign != :(<=)) || (rsign != :(<=))
                constraint_error(args, "Only ranged rows of the form lb <= expr <= ub are supported.")
            end
            ((vectorized = lvectorized) == rvectorized) || constraint_error("Signs are inconsistently vectorized")
            #addconstr = (lvectorized ? :addVectorizedConstraint : :addconstraint)
            x_str = string(x)
            lb_str = string(x.args[1])
            ub_str = string(x.args[5])
            newaff, parsecode = parseExprToplevel(x.args[3],:aff)

            newlb, parselb = parseExprToplevel(x.args[1],:lb)
            newub, parseub = parseExprToplevel(x.args[5],:ub)

            constraintcall = :(constructconstraint!($newaff,$newlb,$newub))

            addkwargs!(constraintcall, kwargs.args)
            code = quote
                aff = zero(AffExpr)
                $parsecode
                lb = 0.0
                $parselb
                ub = 0.0
                $parseub
            end
            if vectorized
                code = quote
                    $code
                    lbval, ubval = $newlb, $newub
                end
            else
                code = quote
                    $code
                    CoefType = coeftype($newaff)
                    try
                        lbval = convert(CoefType, $newlb)
                    catch
                        constraint_error($args, string("Expected ",$lb_str," to be a ", CoefType, "."))
                    end
                    try
                        ubval = convert(CoefType, $newub)
                    catch
                        constraint_error($args, string("Expected ",$ub_str," to be a ", CoefType, "."))
                    end
                end
            end

            code = quote
                $code
                $(refcall) = $constraintcall
            end
        else
            # Unknown
            constraint_error(args, string("Constraints must be in one of the following forms:\n" *
                  "       expr1 <= expr2\n" * "       expr1 >= expr2\n" *
                  "       expr1 == expr2\n" * "       lb <= expr <= ub"))
        end

    creation_code = getloopedcode(variable, code, condition, idxvars, idxsets, idxpairs, :AbstractConstraint)

    if anonvar
        macro_code = macro_return(creation_code, variable)
    else
        macro_code = macro_assign_and_return(creation_code, variable, getname(c))
    end
end

"""
    @linkconstraint(graph,args...)
    macro for defining linkconstraints between nodes and edges.  Link constraints are associated with nodes and edges within their respective graph.
"""
macro linkconstraint(graph,args...)
    #Check the inputs are the correct types.  This needs to throw
    checkinputs = quote
        #@assert Plasmo.is_graphmodel($m)
        @assert isa($graph,AbstractModelGraph)
    end
    #generate constraint list and them to node or edge linkdata
    refscode = quote
        cons_refs = @getconstraintlist($(args...))           #returns all of the constraints that would be generated from the expression

        if isa(cons_refs,JuMP.JuMPArray)
            cons_refs = cons_refs.innerArray
        elseif isa(cons_refs,JuMP.JuMPDict)
            cons_refs = collect(values(cons_refs.tupledict))
        end
        addlinkconstraint($graph,cons_refs)    #add the link constraints to the node or edge and map to graph
    end
    # return quote
    #     begin
    #         $checkinputs
    #         $refscode
    #     end
    # end
    return esc(quote
        begin
            $checkinputs
            $refscode
        end
    end)
end

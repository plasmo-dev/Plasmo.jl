using Base.Meta

#macro function helpers
_get_name(c::Symbol) = c
_get_name(c::Nothing) = ()
_get_name(c::AbstractString) = c
function _get_name(c::Expr)
    if c.head == :string
        return c
    else
        return c.args[1]
    end
end

"""
    @optinode(optigraph, expr...)

Add a new optinode to `optigraph`. The expression `expr` can either be

* of the form `nodename` creating a single optinode with the variable name `varname`
* of the form `nodename[...]` or `[...]` creating a container of optinodes using JuMP Containers

"""
macro optinode(graph, args...)
    #check arguments
    @assert length(args) <= 1
    #get the name passed into the macro expression
    if length(args) == 0
        macro_code = :(add_node!($graph))
    else
        var = string(_get_name(args[1]))
        macro_code = quote
            container = JuMP.Containers.@container($(args...), add_node!($graph))
            #set node labels
            if isa(container, OptiNode)
                container.label = $var
            else
                axs = axes(container)
                terms = collect(Base.Iterators.product(axs...))[:]
                for (i, node) in enumerate(container)
                    node.label = $var * "[$(string(terms[i]...))]"
                end
            end
            $(graph).obj_dict[Symbol($var)] = container
        end
    end
    return esc(macro_code)
end

#node is deprecated
macro node(graph, args...)
    code = quote
        @warn "@node is deprecated.  Use @optinode for future applications"
        @optinode($graph, $(args...))
    end
    return esc(code)
end

"""
    @linkconstraint(graph::OptiGraph, expr)

Add a linking constraint described by the expression `expr`.

    @linkconstraint(graph::OptiGraph, ref[i=..., j=..., ...], expr)

Add a group of linking  constraints described by the expression `expr` parametrized by
`i`, `j`, ...

The @linkconstraint macro works the same way as the `JuMP.@constraint` macro.
"""
macro linkconstraint(graph_or_edge, args...)
    args, kw_args, requestedcontainer = Containers._extract_kw_args(args)
    attached_node_kw_args = filter(kw -> kw.args[1] == :attach, kw_args)
    #extra_kw_args = filter(kw -> kw.args[1] != :attach, kw_args)

    #check for attached node argumentss
    if length(attached_node_kw_args) > 0
        attached_node = attached_node_kw_args[1].args[2]
    else
        attached_node = nothing
    end

    code = quote
        @assert isa($graph_or_edge, Union{AbstractOptiGraph,OptiEdge})  #Check the inputs are the correct types.  This needs to throw

        refs = JuMP.@constraint($graph_or_edge, ($(args...)))

        #BUG: need to unfold attached node arguments.  It isn't grabbing the correct
        #Set attached node if argument was provided
        if $attached_node != nothing
            if isa(refs, LinkConstraintRef)
                link = LinkConstraint(refs)
                set_attached_node(link, $attached_node)
            else
                links = LinkConstraint.(refs)
                for link in links
                    set_attached_node(link, $attached_node)
                end
            end
        end
        refs
    end
    return esc(code)
end

"""
    @NLnodeconstraint(node,args...)

Add a nonlinear constraint to an optinode.  Wraps JuMP.@NLconstraint.  This method will deprecate once optinodes
extend nonlinear JuMP functionality.
"""
macro NLnodeconstraint(node, args...)
    code = quote
        @warn "@NLnodeconstraint is deprecated.  Use @NLconstraint for future applications"
        JuMP.@NLconstraint($node, ($(args...)))
    end
    return esc(code)
end

macro NLnodeobjective(node, args...)
    code = quote
        @warn "@NLnodeobjective is deprecated.  Use @NLobjective for future applications"
        JuMP.@NLobjective($node, ($(args...)))
    end
    return esc(code)
end
